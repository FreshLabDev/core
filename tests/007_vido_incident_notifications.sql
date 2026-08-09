\set ON_ERROR_STOP on

INSERT INTO core.person(telegram_user_id, tg_language_code)
VALUES (7001, 'en')
ON CONFLICT (telegram_user_id) DO NOTHING;
INSERT INTO core.chat(chat_id, type)
VALUES (7001, 'private')
ON CONFLICT (chat_id) DO NOTHING;

SET ROLE vido_core;
INSERT INTO vido.incident_notifications(
  incident_key, chat_id, chat_type, language, message_html
) VALUES (
  'test-incident', 7001, 'private', 'en', '<b>Test</b>'
);

UPDATE vido.incident_notifications
   SET status = 'sending',
       attempts = attempts + 1,
       lease_owner = 'test-worker',
       lease_expires_at = now() + interval '1 minute',
       last_attempt_at = now()
 WHERE incident_key = 'test-incident' AND chat_id = 7001;

UPDATE vido.incident_notifications
   SET status = 'sent',
       telegram_message_id = 70001,
       sent_at = now(),
       lease_owner = NULL,
       lease_expires_at = NULL
 WHERE incident_key = 'test-incident' AND chat_id = 7001;

SELECT EXISTS (
  SELECT 1 FROM vido.incident_notifications
   WHERE incident_key = 'test-incident'
     AND chat_id = 7001
     AND status = 'sent'
     AND attempts = 1
     AND telegram_message_id = 70001
) AS lifecycle_recorded \gset
\if :lifecycle_recorded
\else
  \quit 1
\endif

DO $$
BEGIN
  INSERT INTO vido.incident_notifications(
    incident_key, chat_id, chat_type, language, message_html, status
  ) VALUES (
    'invalid-incident', 7001, 'private', 'en', '<b>Invalid</b>', 'sent'
  );
  RAISE EXCEPTION 'sent notification without Telegram evidence was accepted';
EXCEPTION WHEN check_violation THEN
  NULL;
END $$;
RESET ROLE;

SELECT has_table_privilege(
  'vido_core', 'vido.incident_notifications', 'SELECT,INSERT,UPDATE'
) AS vido_can_use_outbox \gset
\if :vido_can_use_outbox
\else
  \quit 1
\endif

SELECT NOT has_table_privilege(
  'searchy_core', 'vido.incident_notifications', 'SELECT'
) AS searchy_isolated \gset
\if :searchy_isolated
\else
  \quit 1
\endif

SELECT NOT has_table_privilege(
  'public', 'vido.incident_notifications', 'SELECT'
) AS public_isolated \gset
\if :public_isolated
\else
  \quit 1
\endif
