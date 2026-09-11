//! FRB surface: everything the Flutter UI can call.

use std::sync::OnceLock;

use anyhow::Result;
use serde::{Deserialize, Serialize};

use crate::frb_generated::StreamSink;

use crate::engine::events::Event;
use crate::engine::models::{ContentKind, Playlist, ProbeInfo, SearchHistoryEntry, SortOrder, Track};
use crate::engine::{pipeline, AppEngine};

/// The single shared engine instance.
static ENGINE: OnceLock<AppEngine> = OnceLock::new();

fn engine_ref() -> &'static AppEngine {
    ENGINE
        .get()
        .expect("engine not initialized: call RustLib.init() first")
}

/// Initialize the engine (directories, SQLite, settings) and start background
/// workers. Called once from `RustLib.init()`.
#[flutter_rust_bridge::frb(init)]
pub async fn init_app() -> Result<()> {
    flutter_rust_bridge::setup_default_user_utils();
    if ENGINE.get().is_some() {
        return Ok(());
    }
    let engine = AppEngine::init().await?;
    let _ = ENGINE.set(engine);

    // Kick off the yt-dlp version check self-update in the background.
    let engine = engine_ref().clone();
    tokio::spawn(async move {
        let _ = crate::engine::ytdlp::check_and_update(&engine).await;
    });
    Ok(())
}

// ---- downloads ----------------------------------------------------------

/// Query metadata for a URL without downloading anything.
#[flutter_rust_bridge::frb]
pub async fn probe_url(url: String) -> Result<ProbeInfo> {
    crate::engine::downloader::probe(&url).await
}

/// Start a download+convert task. Returns a task id; progress and result are
/// delivered on the event stream.
#[flutter_rust_bridge::frb]
pub async fn start_download(url: String, kind: ContentKind) -> Result<String> {
    pipeline::start_download(engine_ref(), url, kind)
}

/// Cancel a running download task.
#[flutter_rust_bridge::frb]
pub async fn cancel_download(task_id: String) -> Result<()> {
    engine_ref().cancel_download(&task_id).await
}

/// Number of currently active downloads.
#[flutter_rust_bridge::frb]
pub async fn active_download_count() -> Result<i64> {
    Ok(engine_ref().active_downloads().await as i64)
}

// ---- library ------------------------------------------------------------

#[flutter_rust_bridge::frb]
pub async fn get_library(search: Option<String>, order: SortOrder) -> Result<Vec<Track>> {
    engine_ref().db.list_tracks(search.as_deref(), order).await
}

#[flutter_rust_bridge::frb]
pub async fn get_track(id: String) -> Result<Option<Track>> {
    engine_ref().db.get_track(&id).await
}

/// Delete a track from the library and remove its cached files.
#[flutter_rust_bridge::frb]
pub async fn delete_track(id: String) -> Result<Option<Track>> {
    let engine = engine_ref();
    let track = engine.db.delete_track(&id).await?;
    if let Some(t) = &track {
        let _ = std::fs::remove_file(&t.file_path);
        if let Some(thumb) = &t.thumbnail_path {
            let _ = std::fs::remove_file(thumb);
        }
        engine.emit(Event::LibraryChanged);
    }
    Ok(track)
}

/// Record a playback: bumps play_count and stamps last_played.
#[flutter_rust_bridge::frb]
pub async fn record_play(id: String) -> Result<()> {
    engine_ref()
        .db
        .record_play(&id, &chrono::Utc::now().to_rfc3339())
        .await
}

// ---- playlists ----------------------------------------------------------

#[flutter_rust_bridge::frb]
pub async fn create_playlist(name: String) -> Result<Playlist> {
    engine_ref().db.create_playlist(&name).await
}

#[flutter_rust_bridge::frb]
pub async fn rename_playlist(id: String, name: String) -> Result<()> {
    engine_ref().db.rename_playlist(&id, &name).await
}

#[flutter_rust_bridge::frb]
pub async fn delete_playlist(id: String) -> Result<()> {
    let engine = engine_ref();
    engine.db.delete_playlist(&id).await?;
    engine.emit(Event::LibraryChanged);
    Ok(())
}

#[flutter_rust_bridge::frb]
pub async fn list_playlists() -> Result<Vec<Playlist>> {
    engine_ref().db.list_playlists().await
}

#[flutter_rust_bridge::frb]
pub async fn add_to_playlist(playlist_id: String, track_id: String) -> Result<()> {
    engine_ref()
        .db
        .add_to_playlist(&playlist_id, &track_id)
        .await
}

#[flutter_rust_bridge::frb]
pub async fn remove_from_playlist(playlist_id: String, track_id: String) -> Result<()> {
    engine_ref()
        .db
        .remove_from_playlist(&playlist_id, &track_id)
        .await
}

#[flutter_rust_bridge::frb]
pub async fn reorder_playlist(playlist_id: String, ordered_track_ids: Vec<String>) -> Result<()> {
    engine_ref()
        .db
        .reorder_playlist(&playlist_id, &ordered_track_ids)
        .await
}

#[flutter_rust_bridge::frb]
pub async fn playlist_tracks(playlist_id: String) -> Result<Vec<Track>> {
    engine_ref().db.playlist_tracks(&playlist_id).await
}

// ---- search history ------------------------------------------------------

#[flutter_rust_bridge::frb]
pub async fn record_search(query: String, source: String) -> Result<()> {
    engine_ref().db.record_search(&query, &source).await
}

#[flutter_rust_bridge::frb]
pub async fn recent_searches(source: String, limit: i64) -> Result<Vec<SearchHistoryEntry>> {
    engine_ref().db.recent_searches(&source, limit).await
}

#[flutter_rust_bridge::frb]
pub async fn delete_search(id: i64) -> Result<()> {
    engine_ref().db.delete_search(id).await
}

// ---- settings -----------------------------------------------------------

#[flutter_rust_bridge::frb]
pub async fn get_setting(key: String) -> Result<Option<String>> {
    engine_ref().db.get_setting(&key).await
}

#[flutter_rust_bridge::frb]
pub async fn set_setting(key: String, value: String) -> Result<()> {
    engine_ref().db.set_setting(&key, &value).await
}

#[derive(Serialize, Deserialize)]
pub struct AppDirs {
    pub home: String,
    pub cache: String,
    pub thumbs: String,
    pub tmp: String,
}

#[flutter_rust_bridge::frb]
pub async fn app_dirs() -> Result<AppDirs> {
    let engine = engine_ref();
    Ok(AppDirs {
        home: crate::engine::paths::app_home()
            .to_string_lossy()
            .to_string(),
        cache: engine.cache_dir.to_string_lossy().to_string(),
        thumbs: engine.thumbs_dir.to_string_lossy().to_string(),
        tmp: engine.tmp_dir.to_string_lossy().to_string(),
    })
}

// ---- yt-dlp -------------------------------------------------------------

#[derive(Serialize, Deserialize)]
pub struct YtdlpInfo {
    pub present: bool,
    pub version: Option<String>,
    pub outdated: bool,
    pub last_checked: Option<String>,
}

/// Snapshot of the last yt-dlp check (from persisted settings).
#[flutter_rust_bridge::frb]
pub async fn get_ytdlp_status() -> Result<YtdlpInfo> {
    let db = &engine_ref().db;
    let version = db.get_setting(crate::engine::SETTING_YTDLP_VERSION).await?;
    let last_checked = db
        .get_setting(crate::engine::SETTING_YTDLP_CHECKED_AT)
        .await?;
    let present = crate::engine::process::ytdlp_bin().is_some();
    let outdated = version
        .as_deref()
        .map(crate::engine::ytdlp::is_outdated)
        .unwrap_or(true);
    Ok(YtdlpInfo {
        present,
        version,
        outdated,
        last_checked,
    })
}

/// Run the yt-dlp check/update in the background. Results arrive as a
/// `YtdlpStatus` event.
#[flutter_rust_bridge::frb]
pub async fn check_ytdlp() -> Result<()> {
    let engine = engine_ref().clone();
    tokio::spawn(async move {
        let _ = crate::engine::ytdlp::check_and_update(&engine).await;
    });
    Ok(())
}

// ---- engine binaries (mobile) -------------------------------------------

#[derive(Serialize, Deserialize)]
pub struct BinariesStatus {
    pub yt_dlp_present: bool,
    pub ffmpeg_present: bool,
    pub bin_dir: String,
}

/// Presence of the runtime binaries used by the engine. On mobile the app
/// downloads them into `bin_dir`; on desktop they live in PATH.
#[flutter_rust_bridge::frb]
pub async fn binaries_status() -> Result<BinariesStatus> {
    Ok(BinariesStatus {
        yt_dlp_present: crate::engine::process::ytdlp_bin().is_some(),
        ffmpeg_present: crate::engine::process::ffmpeg_bin().is_some(),
        bin_dir: crate::engine::paths::bin_dir()
            .to_string_lossy()
            .to_string(),
    })
}

/// Download yt-dlp + ffmpeg into the app binary dir. Only implemented for
/// Android for now (iOS still needs a reliable static binary source — TODO).
#[flutter_rust_bridge::frb]
pub async fn download_mobile_binaries() -> Result<()> {
    #[cfg(not(target_os = "android"))]
    {
        let _ = engine_ref();
        anyhow::bail!(
            "La descarga automática de binarios solo está implementada en Android por ahora (iOS: TODO)."
        );
    }

    #[cfg(target_os = "android")]
    {
        let db = &engine_ref().db;
        let yt_url = db
            .get_setting("binary.ytdlp_url")
            .await?
            .unwrap_or_else(|| DEFAULT_YTDLP_URL.to_string());
        let ff_url = db
            .get_setting("binary.ffmpeg_url")
            .await?
            .unwrap_or_else(|| DEFAULT_FFMPEG_URL.to_string());

        crate::engine::process::download_binary("yt-dlp", &yt_url).await?;
        crate::engine::process::download_binary("ffmpeg", &ff_url).await?;
        Ok(())
    }
}

// ---- events -------------------------------------------------------------

/// Subscribe to engine events. The returned stream must be listened to as a
/// native Dart stream (`RustStreamSink`).
#[flutter_rust_bridge::frb]
pub async fn event_stream(sink: StreamSink<Event>) -> Result<()> {
    use std::collections::HashMap;
    use std::time::Duration;

    let mut rx = engine_ref().subscribe_events();
    tokio::spawn(async move {
        // Coalescing forwarder. A long download emits many progress events far
        // faster than the UI consumes them, and a full broadcast buffer used to
        // kill the whole stream (`Lagged`), silently dropping the terminal
        // events the UI depends on (finished/cancelled/failed). Here progress
        // snapshots are collapsed to the newest one per task and flushed a few
        // times a second, so the live bar still moves, while every non-progress
        // event is always forwarded and Lagged is treated as "skip stale data".
        const FLUSH_INTERVAL: Duration = Duration::from_millis(300);
        let mut pending: HashMap<String, Event> = HashMap::new();

        loop {
            let (ev, tick) = tokio::select! {
                r = rx.recv() => match r {
                    Ok(ev) => (Some(ev), false),
                    Err(tokio::sync::broadcast::error::RecvError::Lagged(_)) => (None, false),
                    Err(tokio::sync::broadcast::error::RecvError::Closed) => return,
                },
                _ = tokio::time::sleep(FLUSH_INTERVAL) => (None, true),
            };

            if let Some(ev) = ev {
                match &ev {
                    Event::DownloadProgress { task_id, .. } => {
                        pending.insert(task_id.clone(), ev);
                    }
                    _ => {
                        // Send the freshest progress before any terminal event
                        // so the UI lands on the final percentage.
                        for e in pending.drain().map(|(_, e)| e) {
                            if sink.add(e).is_err() {
                                return;
                            }
                        }
                        if sink.add(ev).is_err() {
                            return;
                        }
                        continue;
                    }
                }
            }

            if tick {
                for e in pending.drain().map(|(_, e)| e) {
                    if sink.add(e).is_err() {
                        return;
                    }
                }
            }
        }
    });
    Ok(())
}
