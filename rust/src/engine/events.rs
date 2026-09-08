//! Real-time events emitted by the engine and forwarded to the UI.

use serde::Serialize;

use crate::engine::models::Track;

#[derive(Debug, Clone, Serialize)]
pub enum Event {
    /// Progress of an active download task.
    DownloadProgress {
        task_id: String,
        percent: f32,
        downloaded_bytes: u64,
        total_bytes: Option<u64>,
        speed_bytes_sec: Option<u64>,
        eta_secs: Option<u64>,
    },
    /// A download finished and the track was persisted.
    DownloadFinished { task_id: String, track: Track },
    /// A download failed (reason is human readable, in the app language).
    DownloadFailed { task_id: String, reason: String },
    /// The user cancelled the task.
    DownloadCancelled { task_id: String },
    /// The source was already present in the library; nothing was downloaded.
    DownloadSkippedDuplicate { task_id: String, track: Track },
    /// Result of a background yt-dlp version check / update.
    YtdlpStatus {
        present: bool,
        version: Option<String>,
        outdated: bool,
        last_checked: Option<String>,
        message: Option<String>,
    },
    /// Generic UI notification (e.g. snackbar).
    Notify { kind: String, message: String },
    /// Something that affects the library changed.
    LibraryChanged,
}
