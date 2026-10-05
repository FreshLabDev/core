\set ON_ERROR_STOP on

SET ROLE vido_core;

INSERT INTO vido.group_archive_messages(
  chat_id, message_id, sender_id, sender_name, sent_at, text
) VALUES (-1009001, 1, 501, 'Ann', now(), 'hello');

INSERT INTO vido.group_archive_messages(
  chat_id, message_id, sender_id, sender_name, sent_at, media_kind, media_state
) VALUES (-1009001, 2, 502, 'Bob', now(), 'round', 'queued');

UPDATE vido.group_archive_messages
   SET media_state = 'done',
       media_file = repeat('a', 64) || '.mp4'
 WHERE chat_id = -1009001 AND message_id = 2;

SELECT (
  SELECT count(*) FROM vido.group_archive_messages
   WHERE chat_id = -1009001
     AND ((message_id = 1 AND media_state = 'none')
       OR (message_id = 2 AND media_state = 'done' AND media_file LIKE '%.mp4'))
) = 2 AS archive_recorded \gset
\if :archive_recorded
\else
  DO $$ BEGIN RAISE EXCEPTION 'contract failed: 015_vido_group_archive.sql: expected archive_recorded to be true'; END $$;
\endif

DO $$
BEGIN
  INSERT INTO vido.group_archive_messages(chat_id, message_id, sent_at)
  VALUES (7001, 1, now());
  RAISE EXCEPTION 'private chat id was accepted into the group archive';
EXCEPTION WHEN check_violation THEN
  NULL;
END $$;

DO $$
BEGIN
  INSERT INTO vido.group_archive_messages(
    chat_id, message_id, sent_at, media_kind, media_state, media_file
  ) VALUES (-1009001, 3, now(), 'photo', 'queued', repeat('b', 64) || '.jpg');
  RAISE EXCEPTION 'a file name on a media row that is not done was accepted';
EXCEPTION WHEN check_violation THEN
  NULL;
END $$;

DO $$
BEGIN
  INSERT INTO vido.group_archive_messages(
    chat_id, message_id, sent_at, media_kind, media_state, media_file
  ) VALUES (-1009001, 4, now(), 'photo', 'done', '../../etc/passwd');
  RAISE EXCEPTION 'a path in media_file was accepted';
EXCEPTION WHEN check_violation THEN
  NULL;
END $$;

DO $$
BEGIN
  DELETE FROM vido.group_archive_messages WHERE chat_id = -1009001;
  RAISE EXCEPTION 'vido_core was able to delete archived messages';
EXCEPTION WHEN insufficient_privilege THEN
  NULL;
END $$;

RESET ROLE;
DELETE FROM vido.group_archive_messages WHERE chat_id = -1009001;
