-- core :: 016 - Vido bridge jobs record which download provider served them
-- The central migrator owns the transaction; do not add BEGIN/COMMIT here.
--
-- Vido 2.5 moves platforms from yt-dlp to its own downloaders and keeps
-- yt-dlp and gallery-dl as recovery. Until now the only record of which one
-- delivered was the worker log, which every redeploy erases.
--
-- provider is the downloader id that served the job (tiktok_native, yt_dlp,
-- gallery_dl, ...), a cache Vido answered from (file_ref_cache,
-- artifact_cache, failure_cache, oversized_cache), or the last provider tried
-- when none delivered. fallback_from and fallback_reason name the first
-- provider that failed before another one was tried, and its error reason.
-- All three are plain text written by Vido and NULL for older rows; vido_core
-- already holds UPDATE on the whole table (004).

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

ALTER TABLE vido.bridge_jobs
  ADD COLUMN IF NOT EXISTS provider text,
  ADD COLUMN IF NOT EXISTS fallback_from text,
  ADD COLUMN IF NOT EXISTS fallback_reason text;
