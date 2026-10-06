-- core :: 014 - Vido broadcasts: one durable outbox row per destination chat
-- The central migrator owns the transaction; do not add BEGIN/COMMIT here.
--
-- A broadcast goes to every private chat and group Vido has seen. Private chats
-- last seen before July 2026 were recorded with presence chat_id 0 and have no
-- core.chat row, so chat_id is a bare Telegram id here, not a foreign key; the
-- sign check below keeps private and group ids apart instead.
--
-- Same delivery contract as 007: a row handed to Telegram without an answer
-- becomes delivery_unknown and is never replayed. outcome records why a chat
-- was or was not reached, which is what the operator report counts. The
-- outcome checks spell out IS NOT NULL: a NULL inside IN (...) would make the
-- whole CHECK NULL, and PostgreSQL accepts a NULL check.

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

CREATE TABLE IF NOT EXISTS vido.broadcasts (
  broadcast_key   text PRIMARY KEY,
  manifest_sha256 text NOT NULL,
  photo_sha256    text,
  photo_file_id   text,
  prepared_at     timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  CHECK (broadcast_key <> ''),
  CHECK (manifest_sha256 ~ '^[0-9a-f]{64}$'),
  CHECK (photo_sha256 IS NULL OR photo_sha256 ~ '^[0-9a-f]{64}$'),
  CHECK (photo_file_id IS NULL OR photo_sha256 IS NOT NULL)
);

CREATE TABLE IF NOT EXISTS vido.broadcast_deliveries (
  broadcast_key       text NOT NULL REFERENCES vido.broadcasts(broadcast_key),
  chat_id             bigint NOT NULL,
  chat_type           text NOT NULL,
  language            text NOT NULL,
  message_html        text NOT NULL,
  status              text NOT NULL DEFAULT 'pending',
  outcome             text,
  attempts            integer NOT NULL DEFAULT 0,
  next_attempt_at     timestamptz NOT NULL DEFAULT now(),
  lease_owner         text,
  lease_expires_at    timestamptz,
  last_error          text,
  delivered_chat_id   bigint,
  telegram_message_id bigint,
  prepared_at         timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now(),
  last_attempt_at     timestamptz,
  sent_at             timestamptz,
  PRIMARY KEY (broadcast_key, chat_id),
  CHECK (chat_type IN ('private', 'group', 'supergroup')),
  CHECK ((chat_type = 'private' AND chat_id > 0) OR (chat_type <> 'private' AND chat_id < 0)),
  CHECK (language <> ''),
  CHECK (message_html <> ''),
  CHECK (status IN (
    'pending', 'sending', 'sent', 'failed', 'unreachable', 'delivery_unknown'
  )),
  CHECK (attempts >= 0),
  CHECK (
    (status = 'sending' AND lease_owner IS NOT NULL AND lease_expires_at IS NOT NULL)
    OR status <> 'sending'
  ),
  CHECK (
    (status = 'sent'
      AND outcome IS NOT NULL
      AND outcome IN ('delivered', 'text_only')
      AND telegram_message_id IS NOT NULL
      AND delivered_chat_id IS NOT NULL
      AND sent_at IS NOT NULL)
    OR status <> 'sent'
  ),
  CHECK (
    (status = 'unreachable' AND outcome IS NOT NULL AND outcome IN (
      'blocked', 'deactivated', 'not_started', 'removed', 'no_rights', 'not_found'
    ))
    OR status <> 'unreachable'
  ),
  CHECK (status IN ('sent', 'unreachable') OR outcome IS NULL)
);

CREATE INDEX IF NOT EXISTS ix_broadcast_deliveries_ready
  ON vido.broadcast_deliveries (broadcast_key, next_attempt_at, prepared_at)
  WHERE status = 'pending';

CREATE INDEX IF NOT EXISTS ix_broadcast_deliveries_status
  ON vido.broadcast_deliveries (broadcast_key, status);

GRANT SELECT, INSERT, UPDATE ON vido.broadcasts, vido.broadcast_deliveries TO vido_core;
