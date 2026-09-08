//! SQLite persistence layer (sqlx, runtime queries — no build-time DB needed).

use std::path::Path;

use anyhow::{Context, Result};
use sqlx::sqlite::{SqliteConnectOptions, SqliteJournalMode, SqlitePool, SqlitePoolOptions};
use uuid::Uuid;

use crate::engine::models::{Playlist, SortOrder, Track};

#[derive(Clone)]
pub struct AppDatabase {
    pool: SqlitePool,
}

/// Escape LIKE wildcards in user search input.
fn escape_like(input: &str) -> String {
    input
        .replace('\\', "\\\\")
        .replace('%', "\\%")
        .replace('_', "\\_")
}

fn order_clause(order: SortOrder) -> &'static str {
    match order {
        SortOrder::TitleAsc => "ORDER BY title COLLATE NOCASE ASC, download_date DESC",
        SortOrder::TitleDesc => "ORDER BY title COLLATE NOCASE DESC, download_date DESC",
        SortOrder::DateDesc => "ORDER BY download_date DESC",
        SortOrder::DateAsc => "ORDER BY download_date ASC",
    }
}

impl AppDatabase {
    /// Open (creating if needed) the database at `path` and run migrations.
    pub async fn connect(path: &Path) -> Result<AppDatabase> {
        let options = SqliteConnectOptions::new()
            .filename(path)
            .create_if_missing(true)
            .journal_mode(SqliteJournalMode::Wal)
            .foreign_keys(true);
        let pool = SqlitePoolOptions::new()
            .max_connections(5)
            .connect_with(options)
            .await
            .map_err(|e| anyhow::anyhow!("opening database {}: {e:?}", path.display()))?;
        sqlx::migrate!("./migrations")
            .run(&pool)
            .await
            .context("running migrations")?;
        Ok(AppDatabase { pool })
    }

    pub async fn close(&self) {
        self.pool.close().await;
    }

    // ---- tracks --------------------------------------------------------

    pub async fn upsert_track(&self, t: &Track) -> Result<()> {
        sqlx::query(
            r#"
            INSERT INTO tracks (
              id, source_id, network_url, title, artist, album, genre,
              duration_seconds, file_path, thumbnail_path, platform,
              content_kind, bitrate_kbps, download_date, play_count, last_played
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT (source_id) DO UPDATE SET
              network_url      = excluded.network_url,
              title            = excluded.title,
              artist           = excluded.artist,
              album            = excluded.album,
              genre            = excluded.genre,
              duration_seconds = excluded.duration_seconds,
              file_path        = excluded.file_path,
              thumbnail_path   = excluded.thumbnail_path,
              platform         = excluded.platform,
              content_kind     = excluded.content_kind,
              bitrate_kbps     = excluded.bitrate_kbps,
              download_date    = excluded.download_date
            "#,
        )
        .bind(&t.id)
        .bind(&t.source_id)
        .bind(&t.network_url)
        .bind(&t.title)
        .bind(t.artist.as_deref())
        .bind(t.album.as_deref())
        .bind(t.genre.as_deref())
        .bind(t.duration_seconds)
        .bind(&t.file_path)
        .bind(t.thumbnail_path.as_deref())
        .bind(t.platform.as_deref())
        .bind(&t.content_kind)
        .bind(t.bitrate_kbps)
        .bind(&t.download_date)
        .bind(t.play_count)
        .bind(t.last_played.as_deref())
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    pub async fn find_track_by_source(&self, source_id: &str) -> Result<Option<Track>> {
        let row = sqlx::query_as::<_, Track>("SELECT * FROM tracks WHERE source_id = ?")
            .bind(source_id)
            .fetch_optional(&self.pool)
            .await?;
        Ok(row)
    }

    pub async fn get_track(&self, id: &str) -> Result<Option<Track>> {
        let row = sqlx::query_as::<_, Track>("SELECT * FROM tracks WHERE id = ?")
            .bind(id)
            .fetch_optional(&self.pool)
            .await?;
        Ok(row)
    }

    pub async fn list_tracks(&self, search: Option<&str>, order: SortOrder) -> Result<Vec<Track>> {
        let mut sql = String::from("SELECT * FROM tracks");
        let trimmed = search.map(|s| s.trim()).filter(|s| !s.is_empty());
        if let Some(q) = trimmed {
            let like = format!("%{}%", escape_like(q));
            sql.push_str(" WHERE (title LIKE ? ESCAPE '\\' OR artist LIKE ? ESCAPE '\\')");
            sql.push(' ');
            sql.push_str(order_clause(order));
            let rows = sqlx::query_as::<_, Track>(&sql)
                .bind(&like)
                .bind(&like)
                .fetch_all(&self.pool)
                .await?;
            return Ok(rows);
        }
        sql.push(' ');
        sql.push_str(order_clause(order));
        let rows = sqlx::query_as::<_, Track>(&sql)
            .fetch_all(&self.pool)
            .await?;
        Ok(rows)
    }

    /// Delete a track from the DB, returning it so the caller can remove its
    /// cached files. Playlist entries cascade via foreign keys.
    pub async fn delete_track(&self, id: &str) -> Result<Option<Track>> {
        let track = self.get_track(id).await?;
        if track.is_some() {
            sqlx::query("DELETE FROM tracks WHERE id = ?")
                .bind(id)
                .execute(&self.pool)
                .await?;
        }
        Ok(track)
    }

    /// Record a playback: increments play_count and stamps last_played.
    pub async fn record_play(&self, id: &str, timestamp: &str) -> Result<()> {
        sqlx::query("UPDATE tracks SET play_count = play_count + 1, last_played = ? WHERE id = ?")
            .bind(timestamp)
            .bind(id)
            .execute(&self.pool)
            .await?;
        Ok(())
    }

    // ---- playlists -----------------------------------------------------

    pub async fn create_playlist(&self, name: &str) -> Result<Playlist> {
        let id = Uuid::new_v4().to_string();
        let now = chrono::Utc::now().to_rfc3339();
        sqlx::query("INSERT INTO playlists (id, name, created_date) VALUES (?, ?, ?)")
            .bind(&id)
            .bind(name)
            .bind(&now)
            .execute(&self.pool)
            .await?;
        let list = self
            .get_playlist(&id)
            .await?
            .ok_or_else(|| anyhow::anyhow!("playlist was not created"))?;
        Ok(list)
    }

    pub async fn rename_playlist(&self, id: &str, name: &str) -> Result<()> {
        sqlx::query("UPDATE playlists SET name = ? WHERE id = ?")
            .bind(name)
            .bind(id)
            .execute(&self.pool)
            .await?;
        Ok(())
    }

    pub async fn delete_playlist(&self, id: &str) -> Result<()> {
        sqlx::query("DELETE FROM playlists WHERE id = ?")
            .bind(id)
            .execute(&self.pool)
            .await?;
        Ok(())
    }

    pub async fn get_playlist(&self, id: &str) -> Result<Option<Playlist>> {
        let row = sqlx::query_as::<_, Playlist>(
            r#"
            SELECT p.id, p.name, p.created_date,
                   COUNT(pt.track_id) AS track_count
            FROM playlists p
            LEFT JOIN playlist_tracks pt ON pt.playlist_id = p.id
            WHERE p.id = ?
            GROUP BY p.id
            "#,
        )
        .bind(id)
        .fetch_optional(&self.pool)
        .await?;
        Ok(row)
    }

    pub async fn list_playlists(&self) -> Result<Vec<Playlist>> {
        let rows = sqlx::query_as::<_, Playlist>(
            r#"
            SELECT p.id, p.name, p.created_date,
                   COUNT(pt.track_id) AS track_count
            FROM playlists p
            LEFT JOIN playlist_tracks pt ON pt.playlist_id = p.id
            GROUP BY p.id
            ORDER BY p.name COLLATE NOCASE ASC
            "#,
        )
        .fetch_all(&self.pool)
        .await?;
        Ok(rows)
    }

    pub async fn add_to_playlist(&self, playlist_id: &str, track_id: &str) -> Result<()> {
        let next: i64 = sqlx::query_scalar(
            "SELECT COALESCE(MAX(order_index), -1) + 1 FROM playlist_tracks WHERE playlist_id = ?",
        )
        .bind(playlist_id)
        .fetch_one(&self.pool)
        .await?;
        sqlx::query(
            "INSERT OR IGNORE INTO playlist_tracks (playlist_id, track_id, order_index) VALUES (?, ?, ?)",
        )
        .bind(playlist_id)
        .bind(track_id)
        .bind(next)
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    pub async fn remove_from_playlist(&self, playlist_id: &str, track_id: &str) -> Result<()> {
        sqlx::query("DELETE FROM playlist_tracks WHERE playlist_id = ? AND track_id = ?")
            .bind(playlist_id)
            .bind(track_id)
            .execute(&self.pool)
            .await?;
        Ok(())
    }

    /// Rewrite the playlist order atomically from the given ordered track ids.
    pub async fn reorder_playlist(
        &self,
        playlist_id: &str,
        ordered_track_ids: &[String],
    ) -> Result<()> {
        let mut tx = self.pool.begin().await?;
        for (index, track_id) in ordered_track_ids.iter().enumerate() {
            sqlx::query(
                "UPDATE playlist_tracks SET order_index = ? WHERE playlist_id = ? AND track_id = ?",
            )
            .bind(index as i64)
            .bind(playlist_id)
            .bind(track_id)
            .execute(&mut *tx)
            .await?;
        }
        tx.commit().await?;
        Ok(())
    }

    pub async fn playlist_tracks(&self, playlist_id: &str) -> Result<Vec<Track>> {
        let rows = sqlx::query_as::<_, Track>(
            r#"
            SELECT t.* FROM playlist_tracks pt
            JOIN tracks t ON t.id = pt.track_id
            WHERE pt.playlist_id = ?
            ORDER BY pt.order_index ASC
            "#,
        )
        .bind(playlist_id)
        .fetch_all(&self.pool)
        .await?;
        Ok(rows)
    }

    // ---- settings ------------------------------------------------------

    pub async fn get_setting(&self, key: &str) -> Result<Option<String>> {
        let value = sqlx::query_scalar::<_, String>("SELECT value FROM settings WHERE key = ?")
            .bind(key)
            .fetch_optional(&self.pool)
            .await?;
        Ok(value)
    }

    pub async fn set_setting(&self, key: &str, value: &str) -> Result<()> {
        sqlx::query(
            "INSERT INTO settings (key, value) VALUES (?, ?)
             ON CONFLICT (key) DO UPDATE SET value = excluded.value",
        )
        .bind(key)
        .bind(value)
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    pub async fn delete_setting(&self, key: &str) -> Result<()> {
        sqlx::query("DELETE FROM settings WHERE key = ?")
            .bind(key)
            .execute(&self.pool)
            .await?;
        Ok(())
    }

    // ---- misc ----------------------------------------------------------

    /// Total tracks in the library.
    pub async fn track_count(&self) -> Result<i64> {
        let count = sqlx::query_scalar::<_, i64>("SELECT COUNT(*) FROM tracks")
            .fetch_one(&self.pool)
            .await?;
        Ok(count)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::engine::models::ContentKind;
    use tempfile::tempdir;

    fn track(source: &str, title: &str, date: &str) -> Track {
        Track {
            id: Uuid::new_v4().to_string(),
            source_id: format!("youtube:{source}"),
            network_url: format!("https://example.com/watch?v={}", source),
            title: title.to_string(),
            artist: Some("Artist".to_string()),
            album: None,
            genre: None,
            duration_seconds: Some(180),
            file_path: format!("/cache/{}.opus", source),
            thumbnail_path: None,
            platform: Some("youtube".to_string()),
            content_kind: ContentKind::Music.as_str().to_string(),
            bitrate_kbps: Some(96),
            download_date: date.to_string(),
            play_count: 0,
            last_played: None,
        }
    }

    /// Return the DB together with the TempDir guard so the directory
    /// (and the DB file inside it) survives for the whole test.
    async fn test_db() -> (tempfile::TempDir, AppDatabase) {
        let dir = tempdir().unwrap();
        let path = dir.path().join("test.db");
        let db = AppDatabase::connect(&path).await.unwrap();
        (dir, db)
    }

    #[tokio::test]
    async fn tracks_crud_and_dedup() {
        let (_dir, db) = test_db().await;
        db.upsert_track(&track("vid1", "Song One", "2026-01-01T00:00:00Z"))
            .await
            .unwrap();

        let by_source = db
            .find_track_by_source("youtube:vid1")
            .await
            .unwrap()
            .unwrap();
        assert_eq!(by_source.title, "Song One");

        // Re-inserting the same source_id must not create a duplicate row.
        db.upsert_track(&track(
            "vid1",
            "Song One (refreshed)",
            "2026-02-01T00:00:00Z",
        ))
        .await
        .unwrap();
        assert_eq!(db.track_count().await.unwrap(), 1);

        let all = db.list_tracks(None, SortOrder::TitleAsc).await.unwrap();
        assert_eq!(all.len(), 1);
        assert_eq!(all[0].title, "Song One (refreshed)");

        let deleted = db.delete_track(&by_source.id).await.unwrap().unwrap();
        assert_eq!(deleted.file_path, "/cache/vid1.opus");
        assert_eq!(db.track_count().await.unwrap(), 0);
    }

    #[tokio::test]
    async fn search_and_sort() {
        let (_dir, db) = test_db().await;
        let mut t1 = track("a", "Zebra Nights", "2026-01-01T00:00:00Z");
        t1.artist = Some("Lunar".into());
        db.upsert_track(&t1).await.unwrap();
        let mut t2 = track("b", "Alpha Waves", "2026-03-01T00:00:00Z");
        t2.artist = Some("Neon".into());
        db.upsert_track(&t2).await.unwrap();

        let sorted = db.list_tracks(None, SortOrder::TitleAsc).await.unwrap();
        assert_eq!(sorted[0].title, "Alpha Waves");

        let newest = db.list_tracks(None, SortOrder::DateDesc).await.unwrap();
        assert_eq!(newest[0].source_id, "youtube:b");

        // Search matches title OR artist.
        let hits = db
            .list_tracks(Some("luNaR"), SortOrder::TitleAsc)
            .await
            .unwrap();
        assert_eq!(hits.len(), 1);
        assert_eq!(hits[0].source_id, "youtube:a");

        // LIKE escaping: searching for '%' must not match everything.
        let none = db
            .list_tracks(Some("%"), SortOrder::TitleAsc)
            .await
            .unwrap();
        assert!(none.is_empty());

        // Search respects sort order.
        let mut t3 = track("c", "Alpha Echo", "2026-04-01T00:00:00Z");
        t3.artist = Some("Neon".into());
        db.upsert_track(&t3).await.unwrap();
        let hits = db
            .list_tracks(Some("alpha"), SortOrder::TitleAsc)
            .await
            .unwrap();
        assert_eq!(hits.len(), 2);
        assert_eq!(hits[0].title, "Alpha Echo");
        assert_eq!(hits[1].title, "Alpha Waves");
        let hits_desc = db
            .list_tracks(Some("alpha"), SortOrder::TitleDesc)
            .await
            .unwrap();
        assert_eq!(hits_desc[0].title, "Alpha Waves");
        // Blank search behaves like no filter.
        let all = db
            .list_tracks(Some("   "), SortOrder::TitleAsc)
            .await
            .unwrap();
        assert_eq!(all.len(), 3);
    }

    #[tokio::test]
    async fn record_play_stamps() {
        let (_dir, db) = test_db().await;
        let t = track("v", "Song", "2026-01-01T00:00:00Z");
        db.upsert_track(&t).await.unwrap();
        db.record_play(&t.id, "2026-05-05T10:00:00Z").await.unwrap();
        db.record_play(&t.id, "2026-05-06T10:00:00Z").await.unwrap();
        let got = db.get_track(&t.id).await.unwrap().unwrap();
        assert_eq!(got.play_count, 2);
        assert_eq!(got.last_played.as_deref(), Some("2026-05-06T10:00:00Z"));
    }

    #[tokio::test]
    async fn playlist_add_remove_order_cascade() {
        let (_dir, db) = test_db().await;
        let pl = db.create_playlist("Roadtrip").await.unwrap();

        let t1 = track("v1", "One", "2026-01-01T00:00:00Z");
        let t2 = track("v2", "Two", "2026-01-02T00:00:00Z");
        db.upsert_track(&t1).await.unwrap();
        db.upsert_track(&t2).await.unwrap();
        db.add_to_playlist(&pl.id, &t1.id).await.unwrap();
        db.add_to_playlist(&pl.id, &t2.id).await.unwrap();

        let tracks = db.playlist_tracks(&pl.id).await.unwrap();
        assert_eq!(tracks.len(), 2);
        assert_eq!(tracks[0].source_id, "youtube:v1");

        db.reorder_playlist(&pl.id, &[t2.id.clone(), t1.id.clone()])
            .await
            .unwrap();
        let tracks = db.playlist_tracks(&pl.id).await.unwrap();
        assert_eq!(tracks[0].source_id, "youtube:v2");

        db.remove_from_playlist(&pl.id, &t2.id).await.unwrap();
        let tracks = db.playlist_tracks(&pl.id).await.unwrap();
        assert_eq!(tracks.len(), 1);

        // Rename round-trip.
        db.rename_playlist(&pl.id, "Workout").await.unwrap();
        let pl2 = db.get_playlist(&pl.id).await.unwrap().unwrap();
        assert_eq!(pl2.name, "Workout");

        // Deleting a track cascades to the playlist.
        db.delete_track(&t1.id).await.unwrap();
        let pl3 = db.get_playlist(&pl.id).await.unwrap().unwrap();
        assert_eq!(pl3.track_count, 0);

        db.delete_playlist(&pl.id).await.unwrap();
        assert!(db.get_playlist(&pl.id).await.unwrap().is_none());
    }

    #[tokio::test]
    async fn settings_roundtrip() {
        let (_dir, db) = test_db().await;
        assert!(db.get_setting("theme").await.unwrap().is_none());
        db.set_setting("theme", "dark").await.unwrap();
        assert_eq!(
            db.get_setting("theme").await.unwrap().as_deref(),
            Some("dark")
        );
        db.set_setting("theme", "light").await.unwrap();
        assert_eq!(
            db.get_setting("theme").await.unwrap().as_deref(),
            Some("light")
        );
        db.delete_setting("theme").await.unwrap();
        assert!(db.get_setting("theme").await.unwrap().is_none());
    }
}
