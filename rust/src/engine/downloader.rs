//! yt-dlp interaction: metadata probe and command builders for both download
//! strategies (direct streaming to stdout, and disk-based fallback).

use anyhow::{bail, Context, Result};
use serde_json::Value;
use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::time::timeout;

use crate::engine::models::ProbeInfo;
use crate::engine::process::{child_log, null, pipe, sanitize_url, ensure_yt_dlp};

const PROBE_TIMEOUT_SECS: u64 = 90;

fn json_str(v: &Value) -> Option<String> {
    match v {
        Value::String(s) => Some(s.clone()),
        Value::Number(n) => Some(n.to_string()),
        _ => None,
    }
}

/// Extract the `artist`/`creator`/`uploader` else `None`.
fn extract_artist(v: &Value) -> Option<String> {
    for key in ["artist", "creator", "uploader", "channel"] {
        if let Some(s) = json_str(v.get(key)?) {
            return Some(s);
        }
    }
    None
}

fn extract_genre(v: &Value) -> Option<String> {
    match v.get("genre")? {
        Value::String(s) => Some(s.clone()),
        Value::Array(items) => {
            let joined: Vec<&str> = items.iter().filter_map(|x| x.as_str()).collect();
            if joined.is_empty() {
                None
            } else {
                Some(joined.join(", "))
            }
        }
        _ => None,
    }
}

/// Heuristic: is this content more likely speech/podcast than music?
/// Long videos or podcast-ish channel/title keywords push towards speech.
pub fn likely_speech(
    duration_seconds: Option<i64>,
    uploader: Option<&str>,
    title: Option<&str>,
) -> bool {
    if let Some(d) = duration_seconds {
        if d >= 40 * 60 {
            return true;
        }
    }
    let keywords = [
        "podcast",
        "audiobook",
        "audiolibro",
        "charla",
        "talk",
        "entrevista",
        "interview",
        "lectura",
        "lecture",
        "conferencia",
    ];
    let hay = format!(
        "{} {}",
        uploader.unwrap_or("").to_lowercase(),
        title.unwrap_or("").to_lowercase()
    );
    keywords.iter().any(|k| hay.contains(k))
}

/// Query yt-dlp for metadata of a URL without downloading it.
pub async fn probe(url: &str) -> Result<ProbeInfo> {
    let url = sanitize_url(url)?;
    let bin = ensure_yt_dlp().await.context(
        "yt-dlp no está instalado. Instálalo con: brew install yt-dlp (o `pipx install yt-dlp`)",
    )?;

    let mut cmd = child_log(
        &bin,
        &[
            "--dump-json",
            "--no-playlist",
            "--no-warnings",
            "--skip-download",
            "--socket-timeout",
            "30",
            &url,
        ],
        null(),
        pipe(),
        pipe(),
    );

    let out = timeout(
        std::time::Duration::from_secs(PROBE_TIMEOUT_SECS),
        cmd.output(),
    )
    .await
    .map_err(|_| {
        anyhow::anyhow!("el análisis del enlace tardó demasiado (>{PROBE_TIMEOUT_SECS}s)")
    })?
    .map_err(|e| {
        // Provide more context about the error
        let bin_path = bin.to_string_lossy();
        anyhow::anyhow!("error ejecutando yt-dlp ({}): {e}", bin_path)
    })?;

    if !out.status.success() {
        let stderr = String::from_utf8_lossy(&out.stderr);
        let tail = stderr.lines().rev().take(6).collect::<Vec<_>>().join("\n");
        bail!("yt-dlp no pudo analizar el enlace:\n{tail}");
    }

    let stdout = String::from_utf8_lossy(&out.stdout);
    let mut v: Value = serde_json::from_str(stdout.trim())
        .map_err(|e| anyhow::anyhow!("respuesta de yt-dlp no válida: {e}"))?;

    // Some extractors emit a small playlists array; unwrap the first entry.
    if v.get("_type").and_then(|t| t.as_str()) == Some("playlist") {
        let entries = v
            .get_mut("entries")
            .and_then(|e| e.as_array_mut())
            .ok_or_else(|| anyhow::anyhow!("no se encontró ninguna entrada en el enlace"))?;
        let first = entries.first().cloned().context("playlist vacía")?;
        v = first;
    }

    let id = json_str(&v["id"]).unwrap_or_default();
    let extractor = json_str(&v["extractor_key"])
        .or_else(|| json_str(&v["extractor"]))
        .unwrap_or_else(|| "desconocido".to_string());
    let duration = v["duration"].as_f64().map(|f| f.round() as i64);
    let title = json_str(&v["title"]).unwrap_or_else(|| "<sin título>".to_string());
    let uploader = json_str(&v["uploader"]).or_else(|| json_str(&v["creator"]));

    let probe = ProbeInfo {
        source_id: format!("{}:{}", extractor.to_lowercase(), id),
        id,
        title,
        artist: extract_artist(&v),
        album: json_str(&v["album"]),
        genre: extract_genre(&v),
        duration_seconds: duration,
        thumbnail_url: json_str(&v["thumbnail"]),
        platform: Some(extractor.to_lowercase()),
        uploader: uploader.clone(),
        webpage_url: json_str(&v["webpage_url"]),
        estimated_size_bytes: v["filesize_approx"].as_u64(),
        likely_speech: likely_speech(duration, uploader.as_deref(), Some(&v["title"].to_string())),
    };
    Ok(probe)
}

/// Args for strategy A: yt-dlp streams the media to stdout.
pub fn ytdlp_stream_args(url: &str) -> Vec<String> {
    vec![
        "-f".into(),
        "bestaudio/best".into(),
        "-o".into(),
        "-".into(),
        "--no-part".into(),
        "--newline".into(),
        "--no-colors".into(),
        "--no-playlist".into(),
        "--socket-timeout".into(),
        "30".into(),
        url.to_string(),
    ]
}

/// Args for strategy B: yt-dlp downloads to a local temp file.
pub fn ytdlp_disk_args(url: &str, dest_pattern: &str) -> Vec<String> {
    vec![
        "-f".into(),
        "bestaudio/best".into(),
        "-o".into(),
        dest_pattern.to_string(),
        "--newline".into(),
        "--no-colors".into(),
        "--no-playlist".into(),
        "--socket-timeout".into(),
        "30".into(),
        url.to_string(),
    ]
}

/// Streaming read of a (possibly large) stdout JSON line-by-line is not
/// needed here; probe output is small. This helper is used by tests.
pub async fn read_first_line<R: tokio::io::AsyncBufRead + Unpin>(reader: R) -> Result<String> {
    let mut reader = BufReader::new(reader);
    let mut first = String::new();
    let n = reader.read_line(&mut first).await?;
    if n == 0 {
        bail!("sin salida");
    }
    Ok(first)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn heuristic_longs_are_speech() {
        assert!(likely_speech(Some(50 * 60), None, None));
        assert!(likely_speech(Some(120), Some("My Podcast Show"), None));
        assert!(likely_speech(
            Some(120),
            None,
            Some("Episode: Talk with guests")
        ));
        assert!(!likely_speech(Some(180), Some("Official Music"), None));
        assert!(!likely_speech(Some(120), None, Some("Song Title")));
    }

    #[test]
    fn sanitize_rejects_bad_input() {
        assert!(sanitize_url("https://youtube.com/watch?v=x").is_ok());
        assert!(sanitize_url("  https://ok.com  ").is_ok());
        assert!(sanitize_url("javascript:alert(1)").is_err());
        assert!(sanitize_url("file:///etc/passwd").is_err());
        assert!(sanitize_url("https://x.com/a b").is_err());
        assert!(sanitize_url("https://x.com/a\n--exec").is_err());
        assert!(sanitize_url("").is_err());
    }

    #[test]
    fn stream_args_use_argv_not_shell() {
        let args = ytdlp_stream_args("https://youtube.com/watch?v=abc");
        assert!(args.contains(&"-o".to_string()));
        assert!(args.contains(&"-".to_string()));
        assert!(args.iter().any(|a| a.contains("https://")));
    }
}
