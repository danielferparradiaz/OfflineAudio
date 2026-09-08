//! Data models shared across the engine and (via flutter_rust_bridge) the UI.

use serde::{Deserialize, Serialize};
use sqlx::FromRow;

#[derive(Debug, Clone, Serialize, Deserialize, FromRow, PartialEq, Eq)]
pub struct Track {
    pub id: String,
    /// Canonical `{extractor}:{video_id}` used for de-duplication.
    pub source_id: String,
    pub network_url: String,
    pub title: String,
    pub artist: Option<String>,
    pub album: Option<String>,
    pub genre: Option<String>,
    pub duration_seconds: Option<i64>,
    /// Absolute path to the cached `.opus` file (hashed name).
    pub file_path: String,
    pub thumbnail_path: Option<String>,
    pub platform: Option<String>,
    /// `"music"` or `"speech"`.
    pub content_kind: String,
    pub bitrate_kbps: Option<i64>,
    /// RFC3339 UTC.
    pub download_date: String,
    pub play_count: i64,
    pub last_played: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct Playlist {
    pub id: String,
    pub name: String,
    pub created_date: String,
    pub track_count: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub enum ContentKind {
    Music,
    Speech,
    Video,
}

impl ContentKind {
    pub fn as_str(&self) -> &'static str {
        match self {
            ContentKind::Music => "music",
            ContentKind::Speech => "speech",
            ContentKind::Video => "video",
        }
    }

    #[allow(clippy::should_implement_trait)]
    pub fn from_str(s: &str) -> ContentKind {
        match s {
            "speech" => ContentKind::Speech,
            "video" => ContentKind::Video,
            _ => ContentKind::Music,
        }
    }

    /// True for raw video downloads (stored as `.mp4`, no ffmpeg transcode).
    pub fn is_video(&self) -> bool {
        matches!(self, ContentKind::Video)
    }

    /// Opus bitrate in kbps for each kind (video does not use ffmpeg audio
    /// transcoding, so its bitrate is unused).
    pub fn bitrate_kbps(&self) -> u32 {
        match self {
            ContentKind::Music => 96,
            ContentKind::Speech => 32,
            ContentKind::Video => 0,
        }
    }

    /// ffmpeg `-application` value.
    pub fn application(&self) -> &'static str {
        match self {
            ContentKind::Music => "audio",
            ContentKind::Speech => "voip",
            ContentKind::Video => "audio",
        }
    }
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
pub enum SortOrder {
    /// Title A-Z.
    TitleAsc,
    /// Title Z-A.
    TitleDesc,
    /// Newest download first (default).
    DateDesc,
    /// Oldest download first.
    DateAsc,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProbeInfo {
    pub id: String,
    pub source_id: String,
    pub title: String,
    pub artist: Option<String>,
    pub album: Option<String>,
    pub genre: Option<String>,
    pub duration_seconds: Option<i64>,
    pub thumbnail_url: Option<String>,
    pub platform: Option<String>,
    pub uploader: Option<String>,
    pub webpage_url: Option<String>,
    pub estimated_size_bytes: Option<u64>,
    /// True when the content looks more like speech/podcast than music.
    pub likely_speech: bool,
}
