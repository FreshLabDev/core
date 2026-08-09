-- Durable, idempotent incident notifications for Vido.
-- The central migrator owns the transaction; do not add BEGIN/COMMIT here.

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

CREATE TABLE IF NOT EXISTS vido.incident_notifications (
  incident_key        text NOT NULL,
  chat_id             bigint NOT NULL REFERENCES core.chat(chat_id),
  chat_type           text NOT NULL,
  language            text NOT NULL,
  message_html        text NOT NULL,
  status              text NOT NULL DEFAULT 'pending',
  attempts            integer NOT NULL DEFAULT 0,
  next_attempt_at     timestamptz NOT NULL DEFAULT now(),
  lease_owner         text,
  lease_expires_at    timestamptz,
  last_error          text,
  telegram_message_id bigint,
  prepared_at         timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now(),
  last_attempt_at     timestamptz,
  sent_at             timestamptz,
  PRIMARY KEY (incident_key, chat_id),
  CHECK (incident_key <> ''),
  CHECK (chat_type IN ('private', 'group', 'supergroup', 'channel')),
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
    (status = 'sent' AND telegram_message_id IS NOT NULL AND sent_at IS NOT NULL)
    OR status <> 'sent'
  )
);

CREATE INDEX IF NOT EXISTS ix_incident_notifications_ready
  ON vido.incident_notifications (incident_key, next_attempt_at, prepared_at)
  WHERE status = 'pending';

CREATE INDEX IF NOT EXISTS ix_incident_notifications_status
  ON vido.incident_notifications (incident_key, status);

GRANT SELECT, INSERT, UPDATE ON vido.incident_notifications TO vido_core;
