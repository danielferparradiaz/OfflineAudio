//! Application engine: owns storage, filesystem layout, event bus and
//! background download/conversion workers.

use anyhow::Result;
use tokio::sync::broadcast;

use crate::engine::events::Event;
use crate::storage::AppDatabase;
use std::path::PathBuf;
use std::sync::Arc;

pub mod converter;
pub mod downloader;
pub mod events;
pub mod models;
pub mod paths;
pub mod pipeline;
pub mod process;
pub mod progress;
pub mod ytdlp;

pub const SETTING_THEME: &str = "theme";
pub const SETTING_LANGUAGE: &str = "language";
pub const SETTING_YTDLP_VERSION: &str = "ytdlp_version";
pub const SETTING_YTDLP_CHECKED_AT: &str = "ytdlp_checked_at";

/// Capacity of the internal event bus.
const EVENT_CAPACITY: usize = 1024;

#[derive(Clone)]
pub struct AppEngine {
    pub db: AppDatabase,
    pub cache_dir: PathBuf,
    pub thumbs_dir: PathBuf,
    pub tmp_dir: PathBuf,
    pub event_tx: broadcast::Sender<Event>,
    pub tasks: Arc<pipeline::TaskRegistry>,
}

impl AppEngine {
    /// Initialize directories, the SQLite database and default settings.
    pub async fn init() -> Result<AppEngine> {
        paths::ensure_dirs()?;
        let db = AppDatabase::connect(&paths::db_path()).await?;
        let (event_tx, _) = broadcast::channel(EVENT_CAPACITY);
        let engine = AppEngine {
            db,
            cache_dir: paths::cache_dir(),
            thumbs_dir: paths::thumbs_dir(),
            tmp_dir: paths::tmp_dir(),
            event_tx,
            tasks: Arc::new(pipeline::TaskRegistry::new()),
        };
        engine.ensure_default_settings().await?;
        Ok(engine)
    }

    async fn ensure_default_settings(&self) -> Result<()> {
        if self.db.get_setting(SETTING_THEME).await?.is_none() {
            self.db.set_setting(SETTING_THEME, "dark").await?;
        }
        if self.db.get_setting(SETTING_LANGUAGE).await?.is_none() {
            self.db.set_setting(SETTING_LANGUAGE, "es").await?;
        }
        Ok(())
    }

    /// Publish an event to all live subscribers (broadcast).
    pub fn emit(&self, ev: Event) {
        let _ = self.event_tx.send(ev);
    }

    /// Subscribe to engine events (used by the FRB bridge).
    pub fn subscribe_events(&self) -> broadcast::Receiver<Event> {
        self.event_tx.subscribe()
    }

    // ---- task lifecycle helpers ----------------------------------------

    /// Ask a running download to stop. Children are killed by its task loop.
    pub async fn cancel_download(&self, task_id: &str) -> Result<()> {
        self.tasks.cancel(task_id).await;
        Ok(())
    }

    pub async fn active_downloads(&self) -> usize {
        self.tasks.active_count().await
    }
}
