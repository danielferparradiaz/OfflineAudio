-- Listening stats for the expert shuffle: completed listens (reached the
-- end of the track) and total seconds actually listened. play_count alone
-- only counts starts, so these columns tell "loved classics" apart from
-- "started and skipped".

ALTER TABLE tracks ADD COLUMN completed_count INTEGER NOT NULL DEFAULT 0;
ALTER TABLE tracks ADD COLUMN total_listen_seconds INTEGER NOT NULL DEFAULT 0;
