-- OfflineAudio schema init

CREATE TABLE IF NOT EXISTS tracks (
  id               TEXT PRIMARY KEY NOT NULL,
  source_id        TEXT NOT NULL UNIQUE,
  network_url      TEXT NOT NULL,
  title            TEXT NOT NULL,
  artist           TEXT,
  album            TEXT,
  genre            TEXT,
  duration_seconds INTEGER,
  file_path        TEXT NOT NULL,
  thumbnail_path   TEXT,
  platform         TEXT,
  content_kind     TEXT NOT NULL DEFAULT 'music',
  bitrate_kbps     INTEGER,
  download_date    TEXT NOT NULL,
  play_count       INTEGER NOT NULL DEFAULT 0,
  last_played      TEXT
);

CREATE INDEX IF NOT EXISTS idx_tracks_title ON tracks (title COLLATE NOCASE);
CREATE INDEX IF NOT EXISTS idx_tracks_artist ON tracks (artist COLLATE NOCASE);

CREATE TABLE IF NOT EXISTS playlists (
  id           TEXT PRIMARY KEY NOT NULL,
  name         TEXT NOT NULL,
  created_date TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS playlist_tracks (
  playlist_id TEXT NOT NULL REFERENCES playlists(id) ON DELETE CASCADE,
  track_id    TEXT NOT NULL REFERENCES tracks(id) ON DELETE CASCADE,
  order_index INTEGER NOT NULL,
  PRIMARY KEY (playlist_id, track_id)
);

CREATE INDEX IF NOT EXISTS idx_playlist_tracks_order
  ON playlist_tracks (playlist_id, order_index);

CREATE TABLE IF NOT EXISTS settings (
  key   TEXT PRIMARY KEY NOT NULL,
  value TEXT NOT NULL
);