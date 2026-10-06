\set ON_ERROR_STOP on

SET ROLE vido_core;
INSERT INTO vido.broadcasts(broadcast_key, manifest_sha256, photo_sha256)
VALUES ('test-broadcast', repeat('a', 64), repeat('b', 64));

-- A private chat with no core.chat row: the outbox must still accept it.
INSERT INTO vido.broadcast_deliveries(
  broadcast_key, chat_id, chat_type, language, message_html
) VALUES
  ('test-broadcast', 7101, 'private', 'en', '<b>Test</b>'),
  ('test-broadcast', 7102, 'private', 'ru', '<b>Тест</b>'),
  ('test-broadcast', -1007103, 'supergroup', 'en', '<b>Test</b>');

UPDATE vido.broadcast_deliveries
   SET status = 'sending',
       attempts = attempts + 1,
       lease_owner = 'test-worker',
       lease_expires_at = now() + interval '1 minute',
       last_attempt_at = now()
 WHERE broadcast_key = 'test-broadcast' AND chat_id = 7101;

UPDATE vido.broadcast_deliveries
   SET status = 'sent',
       outcome = 'delivered',
       delivered_chat_id = 7101,
       telegram_message_id = 71001,
       sent_at = now(),
       lease_owner = NULL,
       lease_expires_at = NULL
 WHERE broadcast_key = 'test-broadcast' AND chat_id = 7101;

UPDATE vido.broadcast_deliveries
   SET status = 'unreachable',
       outcome = 'blocked',
       attempts = 1,
       last_error = 'Forbidden: bot was blocked by the user'
 WHERE broadcast_key = 'test-broadcast' AND chat_id = 7102;

UPDATE vido.broadcasts
   SET photo_file_id = 'photo-file-id'
 WHERE broadcast_key = 'test-broadcast';

SELECT (
  SELECT count(*) FROM vido.broadcast_deliveries
   WHERE broadcast_key = 'test-broadcast'
     AND ((chat_id = 7101 AND status = 'sent' AND outcome = 'delivered')
       OR (chat_id = 7102 AND status = 'unreachable' AND outcome = 'blocked')
       OR (chat_id = -1007103 AND status = 'pending' AND outcome IS NULL))
) = 3 AS lifecycle_recorded \gset
\if :lifecycle_recorded
\else
  DO $$ BEGIN RAISE EXCEPTION 'contract failed: 014_vido_broadcasts.sql: expected lifecycle_recorded to be true'; END $$;
\endif

DO $$
BEGIN
  INSERT INTO vido.broadcast_deliveries(
    broadcast_key, chat_id, chat_type, language, message_html, status, outcome
  ) VALUES (
    'test-broadcast', 7104, 'private', 'en', '<b>Invalid</b>', 'sent', 'delivered'
  );
  RAISE EXCEPTION 'sent broadcast without Telegram evidence was accepted';
EXCEPTION WHEN check_violation THEN
  NULL;
END $$;

DO $$
BEGIN
  INSERT INTO vido.broadcast_deliveries(
    broadcast_key, chat_id, chat_type, language, message_html, status
  ) VALUES (
    'test-broadcast', 7105, 'private', 'en', '<b>Invalid</b>', 'unreachable'
  );
  RAISE EXCEPTION 'unreachable broadcast without an outcome was accepted';
EXCEPTION WHEN check_violation THEN
  NULL;
END $$;

DO $$
BEGIN
  INSERT INTO vido.broadcast_deliveries(
    broadcast_key, chat_id, chat_type, language, message_html, status,
    delivered_chat_id, telegram_message_id, sent_at
  ) VALUES (
    'test-broadcast', 7107, 'private', 'en', '<b>Invalid</b>', 'sent',
    7107, 71007, now()
  );
  RAISE EXCEPTION 'sent broadcast without an outcome was accepted';
EXCEPTION WHEN check_violation THEN
  NULL;
END $$;

DO $$
BEGIN
  INSERT INTO vido.broadcast_deliveries(
    broadcast_key, chat_id, chat_type, language, message_html
  ) VALUES (
    'test-broadcast', -7106, 'private', 'en', '<b>Invalid</b>'
  );
  RAISE EXCEPTION 'private broadcast target with a group id was accepted';
EXCEPTION WHEN check_violation THEN
  NULL;
END $$;
RESET ROLE;

SELECT has_table_privilege('vido_core', 'vido.broadcasts', 'SELECT,INSERT,UPDATE')
   AND has_table_privilege('vido_core', 'vido.broadcast_deliveries', 'SELECT,INSERT,UPDATE')
   AS vido_can_use_outbox \gset
\if :vido_can_use_outbox
\else
  DO $$ BEGIN RAISE EXCEPTION 'contract failed: 014_vido_broadcasts.sql: expected vido_can_use_outbox to be true'; END $$;
\endif

SELECT NOT has_table_privilege('vido_core', 'vido.broadcast_deliveries', 'DELETE')
   AS vido_cannot_erase_evidence \gset
\if :vido_cannot_erase_evidence
\else
  DO $$ BEGIN RAISE EXCEPTION 'contract failed: 014_vido_broadcasts.sql: expected vido_cannot_erase_evidence to be true'; END $$;
\endif

SELECT NOT has_table_privilege('searchy_core', 'vido.broadcast_deliveries', 'SELECT')
   AND NOT has_table_privilege('searchy_core', 'vido.broadcasts', 'SELECT')
   AS searchy_isolated \gset
\if :searchy_isolated
\else
  DO $$ BEGIN RAISE EXCEPTION 'contract failed: 014_vido_broadcasts.sql: expected searchy_isolated to be true'; END $$;
\endif

SELECT NOT has_table_privilege('public', 'vido.broadcast_deliveries', 'SELECT')
   AS public_isolated \gset
\if :public_isolated
\else
  DO $$ BEGIN RAISE EXCEPTION 'contract failed: 014_vido_broadcasts.sql: expected public_isolated to be true'; END $$;
\endif
