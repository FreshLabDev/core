-- core :: 015 - Vido group archive: a read-only copy of one group's messages
-- The central migrator owns the transaction; do not add BEGIN/COMMIT here.
--
-- Vido records messages of the groups named in GROUP_ARCHIVE_CHAT_IDS and
-- keeps their attachments on disk; the WS04 status site draws them as a
-- messenger. chat_id is a bare Telegram id, not a foreign key: the archive
-- must keep working if the core.chat row is rekeyed or never created.
--
-- media_file is the content hash and extension of the downloaded file
-- (<sha256>.<ext>), the same naming the status site already serves. The text of
-- a message is replaced when Telegram reports an edit; earlier versions are
-- not kept. file_id lets Vido finish a download a restart interrupted.

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

CREATE TABLE IF NOT EXISTS vido.group_archive_messages (
  chat_id             bigint      NOT NULL,
  message_id          bigint      NOT NULL,
  thread_id           bigint,
  sender_id           bigint,
  sender_name         text        NOT NULL DEFAULT '',
  sender_username     text,
  sender_is_bot       boolean     NOT NULL DEFAULT false,
  sent_at             timestamptz NOT NULL,
  edited_at           timestamptz,
  text                text        NOT NULL DEFAULT '',
  entities            jsonb,
  reply_to_message_id bigint,
  forward_from        text,
  media_group_id      text,
  media_kind          text,
  media               jsonb,
  file_id             text,
  media_file          text,
  media_state         text        NOT NULL DEFAULT 'none',
  media_attempts      integer     NOT NULL DEFAULT 0,
  recorded_at         timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (chat_id, message_id),
  CHECK (chat_id < 0),
  CHECK (media_state IN ('none', 'queued', 'done', 'too_big', 'failed')),
  CHECK (media_attempts >= 0),
  CHECK (media_file IS NULL OR media_file ~ '^[0-9a-f]{64}\.[a-z0-9]{1,8}$'),
  CHECK (media_file IS NULL OR media_state = 'done'),
  CHECK (media_kind IS NOT NULL OR media_state = 'none')
);

CREATE INDEX IF NOT EXISTS ix_group_archive_messages_sent
  ON vido.group_archive_messages (chat_id, sent_at);

CREATE INDEX IF NOT EXISTS ix_group_archive_messages_media_queue
  ON vido.group_archive_messages (chat_id, message_id)
  WHERE media_state = 'queued';

GRANT SELECT, INSERT, UPDATE ON vido.group_archive_messages TO vido_core;
