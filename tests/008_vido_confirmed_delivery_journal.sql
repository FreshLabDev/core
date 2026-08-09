\set ON_ERROR_STOP on

INSERT INTO core.person(telegram_user_id, username, first_name)
VALUES (8008, 'journal-test', 'Journal')
ON CONFLICT (telegram_user_id) DO NOTHING;
INSERT INTO core.chat(chat_id, type, title)
VALUES (-1008008, 'supergroup', 'Journal test')
ON CONFLICT (chat_id) DO NOTHING;

SET ROLE searchy_core;
SELECT vido.create_download_intent(
  decode(repeat('88', 32), 'hex'),
  8008, 'video', 'searchy_chat',
  'https://www.example.com/watch/8008?utm_source=test&a=1',
  'tiktok', 'searchy_chat', now() + interval '6 hours', -1008008,
  'journal-test', 'Journal', NULL, 'en', NULL
);
SELECT vido.bind_intent_message(
  decode(repeat('88', 32), 'hex'), 8008, -1008008, 8008
) AS bound \gset
\if :bound
\else
  \quit 1
\endif
SELECT job_id FROM vido.enqueue_searchy_job(
  decode(repeat('88', 32), 'hex'),
  8008, -1008008, NULL, 8008, 'journal:confirmed'
) \gset journal_
RESET ROLE;

UPDATE vido.bridge_jobs SET
  status = 'ready',
  activity_stage = 'uploading_video',
  platform = 'tiktok',
  journal_source_url = 'https://example.com/watch/8008?a=1',
  journal_source_key = encode(
    public.digest('https://example.com/watch/8008?a=1', 'sha256'),
    'hex'
  ),
  delivery_plan = jsonb_build_object(
    'version', 1,
    'job_id', :journal_job_id,
    'activity_stage', 'uploading_video',
    'operations', jsonb_build_array(jsonb_build_object(
      'operation_id', 'media-1',
      'type', 'video',
      'source', jsonb_build_object(
        'kind', 'telegram_file_id',
        'value', 'journal-file-id'
      )
    ))
  ),
  ready_at = now()
WHERE id = :journal_job_id;

-- delivery_unknown is retryable while the source URL and plan are retained.
-- Keep the normalized journal context so a confirmed retry can be counted.
UPDATE vido.bridge_jobs SET status = 'delivery_unknown'
WHERE id = :journal_job_id;
SELECT EXISTS (
  SELECT 1 FROM vido.bridge_jobs
   WHERE id = :journal_job_id
     AND journal_source_key IS NOT NULL
     AND journal_source_url IS NOT NULL
) AS retry_context_retained \gset
\if :retry_context_retained
\else
  \quit 1
\endif
UPDATE vido.bridge_jobs SET status = 'ready'
WHERE id = :journal_job_id;

SET ROLE searchy_core;
SELECT job_id FROM vido.claim_searchy_delivery(
  'journal-worker', 120
) \gset claimed_
SELECT vido.begin_searchy_operation(
  'journal-worker', :claimed_job_id, 'media-1', 'video'
) AS begun \gset
SELECT vido.ack_searchy_operation(
  'journal-worker', :claimed_job_id, 'media-1', 'video', 8008,
  '{}'::jsonb, '[]'::jsonb
) AS acked \gset
SELECT vido.finish_searchy_delivery(
  'journal-worker', :claimed_job_id
) AS finished \gset
\if :begun
\else
  \quit 1
\endif
\if :acked
\else
  \quit 1
\endif
\if :finished
\else
  \quit 1
\endif
RESET ROLE;

SELECT EXISTS (
  SELECT 1
    FROM vido.downloads d
    JOIN vido.videos v ON v.id = d.video_id
   WHERE d.delivery_key = 'bridge:' || :journal_job_id::text
     AND d.user_id = 8008
     AND d.chat_id = -1008008
     AND d.original_url = 'https://www.example.com/watch/8008?utm_source=test&a=1'
     AND v.source_url = 'https://example.com/watch/8008?a=1'
     AND v.platform = 'tiktok'
) AS journal_recorded \gset
\if :journal_recorded
\else
  \quit 1
\endif

SELECT EXISTS (
  SELECT 1 FROM vido.bridge_jobs
   WHERE id = :journal_job_id
     AND status = 'delivered'
     AND source_url IS NULL
     AND journal_source_key IS NULL
     AND journal_source_url IS NULL
) AS terminal_context_cleared \gset
\if :terminal_context_cleared
\else
  \quit 1
\endif

SELECT vido.finish_searchy_delivery(
  'journal-worker', :journal_job_id
) AS duplicate_finish_idempotent \gset
\if :duplicate_finish_idempotent
\else
  \quit 1
\endif

SELECT count(*) = 1 AS exactly_once
  FROM vido.downloads
 WHERE delivery_key = 'bridge:' || :journal_job_id::text \gset
\if :exactly_once
\else
  \quit 1
\endif

DO $$
BEGIN
  INSERT INTO vido.downloads(
    user_id, video_id, chat_id, original_url, delivery_key
  )
  SELECT user_id, video_id, chat_id, original_url, delivery_key
    FROM vido.downloads
   WHERE delivery_key IS NOT NULL
   LIMIT 1;
  RAISE EXCEPTION 'duplicate delivery_key was accepted';
EXCEPTION WHEN unique_violation THEN
  NULL;
END $$;

SELECT has_table_privilege(
  'vido_core', 'vido.downloads', 'SELECT,INSERT,UPDATE,DELETE'
) AS vido_can_write_journal \gset
\if :vido_can_write_journal
\else
  \quit 1
\endif

SELECT count(*) = 4
       AND bool_and(pg_get_userbyid(c.relowner) = 'vido_core') AS vido_owns_journal
  FROM pg_catalog.pg_class c
  JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname = 'vido'
   AND c.relname IN (
     'videos', 'downloads', 'videos_id_seq', 'downloads_id_seq'
   ) \gset
\if :vido_owns_journal
\else
  \quit 1
\endif

SELECT NOT has_table_privilege(
  'searchy_core', 'vido.downloads', 'SELECT'
) AS searchy_table_isolated \gset
\if :searchy_table_isolated
\else
  \quit 1
\endif

INSERT INTO vido.download_intents(
  token_hash, owner_user_id, kind, delivery_mode, source_url, platform,
  source_surface, origin_chat_id, origin_message_id, created_at, expires_at
) VALUES (
  decode(repeat('89', 32), 'hex'), 8008, 'video', 'searchy_chat',
  'https://example.com/watch/strict', 'tiktok', 'searchy_chat',
  -1008008, 8009, now(), now() + interval '6 hours'
);
INSERT INTO vido.bridge_jobs(
  intent_token_hash, request_key, owner_user_id, kind, target_bot,
  target_chat_id, origin_message_id, source_url, platform
) VALUES (
  decode(repeat('89', 32), 'hex'), 'journal:strict', 8008, 'video',
  'searchy', -1008008, 8009, 'https://example.com/watch/strict', 'tiktok'
);

DO $$
BEGIN
  UPDATE vido.bridge_jobs SET status = 'ready'
   WHERE request_key = 'journal:strict';
  RAISE EXCEPTION 'ready job without journal context was accepted';
EXCEPTION WHEN check_violation THEN
  NULL;
END $$;

DO $$
BEGIN
  PERFORM vido.assert_bridge_journal_rollout_ready();
  RAISE EXCEPTION 'queued bridge job was accepted by the rollout guard';
EXCEPTION WHEN SQLSTATE '55000' THEN
  NULL;
END $$;

INSERT INTO vido.download_intents(
  token_hash, owner_user_id, kind, delivery_mode, source_url, platform,
  source_surface, origin_chat_id, origin_message_id, created_at, expires_at
) VALUES (
  decode(repeat('90', 32), 'hex'), 8008, 'video', 'searchy_chat',
  'https://example.com/watch/failed', 'tiktok', 'searchy_chat',
  -1008008, 8010, now(), now() + interval '6 hours'
);
INSERT INTO vido.bridge_jobs(
  intent_token_hash, request_key, owner_user_id, kind, target_bot,
  target_chat_id, origin_message_id, source_url, platform, status,
  settings_snapshot, delivery_plan, journal_source_key, journal_source_url
) VALUES (
  decode(repeat('90', 32), 'hex'), 'journal:failed', 8008, 'video',
  'searchy', -1008008, 8010, 'https://example.com/watch/failed', 'tiktok',
  'failed', '{"send_as_file": false}'::jsonb, '{"version": 1}'::jsonb,
  repeat('a', 64), 'https://example.com/watch/failed'
);

SELECT vido.clear_existing_failed_bridge_context();
SELECT EXISTS (
  SELECT 1 FROM vido.bridge_jobs
   WHERE request_key = 'journal:failed'
     AND source_url IS NULL
     AND settings_snapshot IS NULL
     AND delivery_plan IS NULL
     AND journal_source_key IS NULL
     AND journal_source_url IS NULL
) AS failed_backfill_cleared \gset
\if :failed_backfill_cleared
\else
  \quit 1
\endif
