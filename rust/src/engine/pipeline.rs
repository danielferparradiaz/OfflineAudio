//! Download pipeline orchestration: probe -> dedup -> disk check ->
//! stream (strategy A) with disk-based fallback (strategy B) -> validate ->
//! thumbnail -> persist -> events.

use std::collections::HashMap;
use std::path::{Path, PathBuf};

use anyhow::{bail, Context, Result};
use sha2::{Digest, Sha256};
use tokio::process::Child;
use tokio::sync::Mutex;
use tokio_util::sync::CancellationToken;
use uuid::Uuid;

use crate::engine::converter::{self, AudioMeta};
use crate::engine::downloader::{self, ytdlp_disk_args, ytdlp_stream_args};
use crate::engine::events::Event;
use crate::engine::models::{ContentKind, ProbeInfo, Track};
use crate::engine::paths;
use crate::engine::process::{child_log, null, pipe, read_stderr, sanitize_url, ytdlp_bin};
use crate::engine::progress::parse_progress_line;
use crate::engine::AppEngine;

/// Safety margin added on top of the estimated size for the disk check.
const DISK_MARGIN_BYTES: u64 = 30 * 1024 * 1024;
const MAX_THUMBNAIL_BYTES: u64 = 8 * 1024 * 1024;
/// Hard cap on the (optional) thumbnail fetch so it can never stall a task.
const THUMBNAIL_TIMEOUT_SECS: u64 = 15;

/// Per-task cancellation registry.
#[derive(Default)]
pub struct TaskRegistry {
    tasks: Mutex<HashMap<String, CancellationToken>>,
}

impl TaskRegistry {
    pub fn new() -> Self {
        Self::default()
    }

    pub async fn register(&self, task_id: String, token: CancellationToken) {
        self.tasks.lock().await.insert(task_id, token);
    }

    pub async fn unregister(&self, task_id: &str) {
        self.tasks.lock().await.remove(task_id);
    }

    pub async fn cancel(&self, task_id: &str) {
        let token = self.tasks.lock().await.get(task_id).cloned();
        if let Some(t) = token {
            t.cancel();
        }
    }

    pub async fn active_count(&self) -> usize {
        self.tasks.lock().await.len()
    }
}

/// SHA-256 of the canonical source id, truncated to 16 hex chars, used as the
/// (cache-stable) file stem.
pub fn cache_stem(source_id: &str) -> String {
    let mut hasher = Sha256::new();
    hasher.update(source_id.as_bytes());
    let digest = hasher.finalize();
    digest.iter().take(8).map(|b| format!("{b:02x}")).collect()
}

/// Start an async download task. Returns the task id; progress and the final
/// outcome are delivered over the engine event stream.
pub fn start_download(engine: &AppEngine, url: String, kind: ContentKind) -> Result<String> {
    let url = sanitize_url(&url)?;
    let task_id = Uuid::new_v4().to_string();
    let token = CancellationToken::new();
    let engine = engine.clone();

    let registry = engine.tasks.clone();
    let tid_for_registry = task_id.clone();
    let ev_task_id = task_id.clone();
    let engine_for_task = engine.clone();
    tokio::spawn(async move {
        registry.register(tid_for_registry, token.clone()).await;
        let result =
            run_download_catching(&engine_for_task, &task_id, url, kind, token.clone()).await;
        registry.unregister(&task_id).await;
        match result {
            Ok(DownloadOutcome::Duplicate { track }) => {
                engine_for_task.emit(Event::DownloadSkippedDuplicate {
                    task_id: task_id.clone(),
                    track: *track,
                });
            }
            Ok(_) => {}
            Err(e) => {
                if token.is_cancelled() {
                    engine_for_task.emit(Event::DownloadCancelled { task_id });
                } else {
                    engine_for_task.emit(Event::DownloadFailed {
                        task_id,
                        reason: e.to_string(),
                    });
                }
            }
        }
    });
    Ok(ev_task_id)
}

#[derive(Debug)]
enum DownloadOutcome {
    Done,
    Duplicate { track: Box<Track> },
}

/// Run [`run_download`] converting any internal panic into a normal error so a
/// terminal event is always emitted — the download task must never die
/// silently, otherwise the UI would be stuck showing the last progress.
async fn run_download_catching(
    engine: &AppEngine,
    task_id: &str,
    url: String,
    kind: ContentKind,
    token: CancellationToken,
) -> Result<DownloadOutcome> {
    let fut = run_download(engine, task_id, url, kind, token);
    match std::panic::catch_unwind(std::panic::AssertUnwindSafe(move || fut)) {
        Ok(fut) => fut.await,
        Err(payload) => {
            let msg = payload
                .downcast_ref::<&str>()
                .map(|s| s.to_string())
                .or_else(|| payload.downcast_ref::<String>().cloned())
                .unwrap_or_else(|| "fallo interno desconocido".to_string());
            bail!("fallo interno al finalizar la descarga: {msg}")
        }
    }
}

async fn run_download(
    engine: &AppEngine,
    task_id: &str,
    url: String,
    kind: ContentKind,
    token: CancellationToken,
) -> Result<DownloadOutcome> {
    let probe = downloader::probe(&url).await?;

    if let Some(existing) = engine.db.find_track_by_source(&probe.source_id).await? {
        return Ok(DownloadOutcome::Duplicate {
            track: Box::new(existing),
        });
    }

    // Rough space estimate: duration * audio bitrate + margin.
    if let Some(duration) = probe.duration_seconds {
        let est = (duration as u64) * (kind.bitrate_kbps() as u64) * 1000 / 8 + DISK_MARGIN_BYTES;
        let free = paths::free_disk_bytes(&engine.cache_dir)?;
        if est > free {
            bail!(
                "espacio en disco insuficiente: necesita ~{:.0} MB y quedan {:.0} MB",
                est as f64 / 1024.0 / 1024.0,
                free as f64 / 1024.0 / 1024.0
            );
        }
    }

    let stem = cache_stem(&probe.source_id);
    let output = engine.cache_dir.join(format!("{stem}.opus"));
    let meta = AudioMeta {
        title: Some(probe.title.clone()),
        artist: probe.artist.clone(),
        album: probe.album.clone(),
    };

    let mut res =
        strategy_stream(engine, task_id, &url, &kind, &output, &meta, token.clone()).await;
    if res.is_err() {
        std::fs::remove_file(&output).ok();
        res = strategy_disk(engine, task_id, &url, &kind, &output, &meta, token.clone()).await;
    }
    res?;

    let size = converter::validate_opus(&output, &kind).await?;
    if size == 0 {
        bail!("no se generó contenido de audio");
    }

    let thumbnail_path = fetch_thumbnail(engine, &probe, &stem).await;

    let track = Track {
        id: Uuid::new_v4().to_string(),
        source_id: probe.source_id.clone(),
        network_url: probe.webpage_url.clone().unwrap_or(url.clone()),
        title: probe.title.clone(),
        artist: probe.artist.clone(),
        album: probe.album.clone(),
        genre: probe.genre.clone(),
        duration_seconds: probe.duration_seconds,
        file_path: output.to_string_lossy().to_string(),
        thumbnail_path,
        platform: probe.platform.clone(),
        content_kind: kind.as_str().to_string(),
        bitrate_kbps: Some(kind.bitrate_kbps() as i64),
        download_date: chrono::Utc::now().to_rfc3339(),
        play_count: 0,
        last_played: None,
    };
    engine.db.upsert_track(&track).await?;
    engine.emit(Event::LibraryChanged);
    engine.emit(Event::DownloadFinished {
        task_id: task_id.to_string(),
        track,
    });

    Ok(DownloadOutcome::Done)
}

/// Strategy A: stream yt-dlp stdout directly into ffmpeg stdin.
async fn strategy_stream(
    engine: &AppEngine,
    task_id: &str,
    url: &str,
    kind: &ContentKind,
    output: &Path,
    meta: &AudioMeta,
    token: CancellationToken,
) -> Result<()> {
    let bin = ytdlp_bin().context("yt-dlp no está instalado")?;
    let args = ytdlp_stream_args(url);
    let mut yt = child_log(&bin, &to_refs(&args), null(), pipe(), pipe()).spawn()?;
    let mut ff = converter::convert_from_stdin(kind, output, meta)?
        .stdin(pipe())
        .stdout(null())
        .stderr(pipe())
        .spawn()?;

    run_stream_pair(engine, task_id, &mut yt, &mut ff, output, token).await
}

/// Pipe two children together (yt-dlp stdout -> ffmpeg stdin), streaming
/// yt-dlp progress to the event bus, with cancellation support.
async fn run_stream_pair(
    engine: &AppEngine,
    task_id: &str,
    yt: &mut Child,
    ff: &mut Child,
    output: &Path,
    token: CancellationToken,
) -> Result<()> {
    let mut yt_stdout = yt.stdout.take().context("sin stdout de yt-dlp")?;
    let mut ff_stdin = ff.stdin.take().context("sin stdin de ffmpeg")?;
    let yt_stderr = yt.stderr.take().context("sin stderr de yt-dlp")?;
    let ff_stderr = ff.stderr.take().context("sin stderr de ffmpeg")?;

    let tx = engine.event_tx.clone();
    let tid = task_id.to_string();
    let progress_tx = tx.clone();
    let yt_err = tokio::spawn(async move {
        read_stderr(
            Box::new(yt_stderr),
            300,
            Some(move |line: &str| {
                if let Some(p) = parse_progress_line(line) {
                    let _ = progress_tx.send(Event::DownloadProgress {
                        task_id: tid.clone(),
                        percent: p.percent,
                        downloaded_bytes: p.downloaded_bytes,
                        total_bytes: p.total_bytes,
                        speed_bytes_sec: p.speed_bytes_sec,
                        eta_secs: p.eta_secs,
                    });
                }
            }),
        )
        .await
    });
    let ff_err =
        tokio::spawn(async move { read_stderr(Box::new(ff_stderr), 120, None::<fn(&str)>).await });

    let mut cancelled = false;
    let copy = tokio::io::copy(&mut yt_stdout, &mut ff_stdin);
    let mut copy = Box::pin(copy);
    tokio::select! {
        _ = token.cancelled() => { cancelled = true; }
        r = &mut copy => { r?; }
    }

    // Release the copy borrow and close ffmpeg's stdin. Without this,
    // ffmpeg never sees EOF on pipe:0 and blocks in fflush/exit forever,
    // so `ff.wait()` would hang and the download would never finish.
    drop(copy);
    drop(ff_stdin);
    drop(yt_stdout);

    if cancelled {
        let _ = yt.kill().await;
        let _ = ff.kill().await;
        let _ = yt_err.await;
        let _ = ff_err.await;
        bail!("descarga cancelada");
    }

    // The copy future has already consumed yt_stdout/ff_stdin: on completion
    // ffmpeg saw EOF. Await both processes and collect diagnostics.
    let _ = tx;
    let yt_status = yt.wait().await?;
    let ff_status = ff.wait().await?;
    let _ = yt_err.await;
    let ff_tail = ff_err.await.unwrap_or_default();

    let yt_ok = yt_status.success();
    let ff_ok = ff_status.success();
    let size = std::fs::metadata(output).ok().map(|m| m.len()).unwrap_or(0);
    if !yt_ok || !ff_ok || size == 0 {
        bail!(
            "la descarga/conversión falló (yt-dlp={yt_ok} ffmpeg={ff_ok} bytes={size})\n{}",
            ff_tail.lines().rev().take(4).collect::<Vec<_>>().join("\n")
        );
    }
    Ok(())
}

/// Strategy B: yt-dlp to a temp file, then ffmpeg from file. Used when the
/// extractor cannot stream to stdout or streaming produced invalid output.
async fn strategy_disk(
    engine: &AppEngine,
    task_id: &str,
    url: &str,
    kind: &ContentKind,
    output: &Path,
    meta: &AudioMeta,
    token: CancellationToken,
) -> Result<()> {
    let keyword = format!("dl_{}", Uuid::new_v4().simple());
    paths::ensure_dirs()?;
    let pattern = PathBuf::from(&engine.tmp_dir).join(format!("{keyword}.%(ext)s"));
    let bin = ytdlp_bin().context("yt-dlp no está instalado")?;
    let args = ytdlp_disk_args(url, &pattern.to_string_lossy());

    let mut yt = child_log(&bin, &to_refs(&args), null(), null(), pipe()).spawn()?;
    let yt_stderr = yt.stderr.take().context("sin stderr de yt-dlp")?;
    let tx = engine.event_tx.clone();
    let tid = task_id.to_string();
    let yt_err = tokio::spawn(async move {
        read_stderr(
            Box::new(yt_stderr),
            300,
            Some(move |line: &str| {
                if let Some(p) = parse_progress_line(line) {
                    let _ = tx.send(Event::DownloadProgress {
                        task_id: tid.clone(),
                        percent: p.percent,
                        downloaded_bytes: p.downloaded_bytes,
                        total_bytes: p.total_bytes,
                        speed_bytes_sec: p.speed_bytes_sec,
                        eta_secs: p.eta_secs,
                    });
                }
            }),
        )
        .await
    });

    let yt_status = tokio::select! {
        _ = token.cancelled() => {
            let _ = yt.kill().await;
            bail!("descarga cancelada")
        }
        s = yt.wait() => s?
    };
    let yt_tail = yt_err.await.unwrap_or_default();
    if !yt_status.success() {
        bail!("yt-dlp falló al descargar:\n{}", tail_trim(&yt_tail));
    }

    let input = converter::find_tmp_download(&engine.tmp_dir, &keyword)
        .map_err(|e| anyhow::anyhow!("{e}\n{yt_tail}"))?;

    let mut ff = converter::convert_from_file(kind, &input, output, meta)?
        .stdin(null())
        .stdout(null())
        .stderr(pipe())
        .spawn()?;
    let ff_stderr = ff.stderr.take().context("sin stderr de ffmpeg")?;
    let ff_err =
        tokio::spawn(async move { read_stderr(Box::new(ff_stderr), 120, None::<fn(&str)>).await });

    let ff_status = tokio::select! {
        _ = token.cancelled() => {
            let _ = ff.kill().await;
            let _ = std::fs::remove_file(&input);
            bail!("conversión cancelada")
        }
        s = ff.wait() => s?
    };
    let ff_tail = ff_err.await.unwrap_or_default();

    // Always clean the temp download.
    std::fs::remove_file(&input).ok();

    let ok = ff_status.success()
        && std::fs::metadata(output)
            .map(|m| m.len() > 0)
            .unwrap_or(false);
    if !ok {
        bail!("ffmpeg falló al convertir:\n{}", tail_trim(&ff_tail));
    }
    Ok(())
}

fn tail_trim(text: &str) -> String {
    text.lines()
        .filter(|l| !l.trim().is_empty())
        .rev()
        .take(6)
        .collect::<Vec<_>>()
        .into_iter()
        .rev()
        .collect::<Vec<_>>()
        .join("\n")
}

fn to_refs(args: &[String]) -> Vec<&str> {
    args.iter().map(|s| s.as_str()).collect()
}

async fn fetch_thumbnail(engine: &AppEngine, probe: &ProbeInfo, stem: &str) -> Option<String> {
    let url = probe.thumbnail_url.as_ref()?;
    // Bounded request: a stuck thumbnail server must never block the download
    // task from reaching its terminal state.
    let client = reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(THUMBNAIL_TIMEOUT_SECS))
        .build()
        .ok()?;
    let resp = client.get(url).send().await.ok()?;
    if !resp.status().is_success() {
        return None;
    }
    let bytes = resp.bytes().await.ok()?;
    if bytes.len() as u64 > MAX_THUMBNAIL_BYTES {
        return None;
    }
    let path = engine.thumbs_dir.join(format!("{stem}.jpg"));
    if std::fs::write(&path, bytes).is_ok() {
        Some(path.to_string_lossy().to_string())
    } else {
        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cache_stem_deterministic_and_distinct() {
        let a = cache_stem("youtube:abc");
        let b = cache_stem("youtube:abc");
        assert_eq!(a, b);
        assert_eq!(a.len(), 16);
        assert_ne!(cache_stem("youtube:abc"), cache_stem("soundcloud:abc"));
    }

    #[test]
    fn tail_trim_takes_last_lines() {
        let t = tail_trim("a\nb\nc\nd\ne\nf\ng\nh");
        assert!(t.contains('h'));
        assert!(!t.contains('b'));
    }

    #[tokio::test]
    async fn registry_registers_and_cancels() {
        let reg = TaskRegistry::new();
        let token = CancellationToken::new();
        reg.register("t1".to_string(), token.clone()).await;
        assert_eq!(reg.active_count().await, 1);
        reg.cancel("t1").await;
        assert!(token.is_cancelled());
        reg.unregister("t1").await;
        assert_eq!(reg.active_count().await, 0);
    }
}
