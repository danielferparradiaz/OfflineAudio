-- Search history for autocomplete suggestions

CREATE TABLE IF NOT EXISTS search_history (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  query      TEXT NOT NULL,
  source     TEXT NOT NULL DEFAULT 'youtube',
  created_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_search_history_source
  ON search_history (source, created_at DESC);
