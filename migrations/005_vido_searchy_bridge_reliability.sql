-- Vido/Searchy bridge reliability hardening.
-- The central migrator owns the transaction; do not add BEGIN/COMMIT here.

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

-- Pin pgcrypto to public. The database owner is named "core", so relying on
-- the default "$user", public search path would otherwise install it into the
-- core schema and make the qualified calls below fail.
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;

ALTER TABLE vido.delivery_operations
  DROP CONSTRAINT IF EXISTS delivery_operations_status_check;
ALTER TABLE vido.delivery_operations
  ADD CONSTRAINT delivery_operations_status_check
  CHECK (status IN ('pending', 'sending', 'delivered', 'failed', 'delivery_unknown'));

ALTER TABLE vido.bridge_jobs
  ADD COLUMN IF NOT EXISTS status_notified_for text,
  ADD COLUMN IF NOT EXISTS status_notified_at timestamptz,
  ADD COLUMN IF NOT EXISTS notification_lease_owner text,
  ADD COLUMN IF NOT EXISTS notification_lease_expires_at timestamptz;

-- Existing terminal jobs were already handled by the in-memory watcher before
-- this durable notification outbox existed. Do not replay historical notices.
UPDATE vido.bridge_jobs SET
  status_notified_for = status,
  status_notified_at = COALESCE(delivered_at, updated_at)
WHERE target_bot = 'searchy' AND status IN ('failed', 'delivery_unknown')
  AND status_notified_for IS NULL
  -- The migrator records version 5 only after this file succeeds. This makes
  -- the historical backfill run once while keeping direct re-application safe.
  AND NOT EXISTS (
    SELECT 1 FROM core.schema_migrations WHERE version = 5
  );

CREATE INDEX IF NOT EXISTS ix_bridge_jobs_notification
  ON vido.bridge_jobs (status, status_notified_for, notification_lease_expires_at, updated_at)
  WHERE target_bot = 'searchy' AND status IN ('failed', 'delivery_unknown');

CREATE TABLE IF NOT EXISTS vido.delivery_retry_intents (
  token_hash      bytea PRIMARY KEY CHECK (octet_length(token_hash) = 32),
  job_id          bigint NOT NULL REFERENCES vido.bridge_jobs(id) ON DELETE CASCADE,
  owner_user_id   bigint NOT NULL REFERENCES core.person(telegram_user_id),
  chat_id         bigint NOT NULL REFERENCES core.chat(chat_id),
  message_id      bigint NOT NULL,
  created_at      timestamptz NOT NULL DEFAULT now(),
  expires_at      timestamptz NOT NULL,
  consumed_at     timestamptz,
  consumed_request_key text,
  CHECK (expires_at > created_at)
);
ALTER TABLE vido.delivery_retry_intents
  ADD COLUMN IF NOT EXISTS consumed_request_key text;
CREATE INDEX IF NOT EXISTS ix_delivery_retry_intents_expiry
  ON vido.delivery_retry_intents (expires_at);

GRANT SELECT, INSERT, UPDATE, DELETE ON vido.delivery_retry_intents TO vido_core;

CREATE OR REPLACE FUNCTION vido.begin_searchy_operation(
  p_worker_id text,
  p_job_id bigint,
  p_operation_id text,
  p_operation_type text
) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, vido AS $$
DECLARE j vido.bridge_jobs%ROWTYPE;
BEGIN
  SELECT * INTO j FROM vido.bridge_jobs
   WHERE id = p_job_id FOR UPDATE;
  IF NOT FOUND OR j.target_bot <> 'searchy' OR j.status <> 'delivering'
     OR j.lease_owner IS DISTINCT FROM p_worker_id
     OR j.lease_expires_at IS NULL OR j.lease_expires_at <= now() THEN
    RETURN false;
  END IF;

  INSERT INTO vido.delivery_operations(job_id, operation_id, operation_type, status)
  VALUES (p_job_id, p_operation_id, p_operation_type, 'sending')
  ON CONFLICT (job_id, operation_id) DO UPDATE SET
    operation_type = EXCLUDED.operation_type,
    status = CASE WHEN vido.delivery_operations.status = 'delivered'
                  THEN 'delivered' ELSE 'sending' END,
    error_reason = CASE WHEN vido.delivery_operations.status = 'delivered'
                        THEN vido.delivery_operations.error_reason ELSE NULL END,
    updated_at = now();
  RETURN true;
END; $$;

CREATE OR REPLACE FUNCTION vido.renew_searchy_delivery(
  p_worker_id text,
  p_job_id bigint,
  p_lease_seconds integer DEFAULT 900
) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, vido AS $$
BEGIN
  UPDATE vido.bridge_jobs SET
    lease_expires_at = now() + make_interval(secs => GREATEST(30, LEAST(p_lease_seconds, 900))),
    updated_at = now()
  WHERE id = p_job_id AND target_bot = 'searchy' AND status = 'delivering'
    AND lease_owner = p_worker_id AND lease_expires_at > now();
  RETURN FOUND;
END; $$;

CREATE OR REPLACE FUNCTION vido.claim_searchy_delivery(
  p_worker_id text,
  p_lease_seconds integer DEFAULT 120
) RETURNS TABLE(
  job_id bigint,
  owner_user_id bigint,
  target_chat_id bigint,
  target_thread_id bigint,
  origin_message_id bigint,
  delivery_plan jsonb,
  delivered_operation_ids text[]
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, vido AS $$
BEGIN
  -- A worker died after durably recording "sending". Telegram may have accepted
  -- the operation, so never auto-replay it.
  WITH uncertain AS (
    SELECT j.id FROM vido.bridge_jobs j
     WHERE j.target_bot = 'searchy' AND j.status = 'delivering'
       AND j.lease_expires_at < now()
       AND EXISTS (
         SELECT 1 FROM vido.delivery_operations o
          WHERE o.job_id = j.id AND o.status = 'sending'
       )
     FOR UPDATE SKIP LOCKED
  )
  UPDATE vido.bridge_jobs j SET
    status = 'delivery_unknown', error_reason = 'telegram_delivery_unknown',
    user_message_key = 'error.download_failed', retryable = false,
    lease_owner = NULL, lease_expires_at = NULL, updated_at = now(),
    status_notified_for = NULL, status_notified_at = NULL,
    notification_lease_owner = NULL, notification_lease_expires_at = NULL
  FROM uncertain u WHERE j.id = u.id;

  UPDATE vido.artifact_leases l SET
    expires_at = LEAST(l.expires_at, now() + interval '30 minutes')
  WHERE l.released_at IS NULL AND EXISTS (
    SELECT 1 FROM vido.bridge_jobs j
     WHERE j.id = l.job_id AND j.status = 'delivery_unknown'
  );

  RETURN QUERY
  WITH candidate AS (
    SELECT j.id FROM vido.bridge_jobs j
     WHERE j.target_bot = 'searchy'
       AND j.status IN ('ready', 'delivering')
       AND (j.lease_expires_at IS NULL OR j.lease_expires_at < now())
       AND NOT EXISTS (
         SELECT 1 FROM vido.delivery_operations o
          WHERE o.job_id = j.id AND o.status = 'sending'
       )
     ORDER BY j.ready_at NULLS LAST, j.created_at
     FOR UPDATE SKIP LOCKED
     LIMIT 1
  )
  UPDATE vido.bridge_jobs j SET
    status = 'delivering', lease_owner = p_worker_id,
    lease_expires_at = now() + make_interval(secs => GREATEST(30, LEAST(p_lease_seconds, 900))),
    updated_at = now()
  FROM candidate c WHERE j.id = c.id
  RETURNING j.id, j.owner_user_id, j.target_chat_id, j.target_thread_id,
            j.origin_message_id, j.delivery_plan,
            ARRAY(
              SELECT o.operation_id FROM vido.delivery_operations o
               WHERE o.job_id = j.id AND o.status = 'delivered'
               ORDER BY o.operation_id
            );
END; $$;

CREATE OR REPLACE FUNCTION vido.ack_searchy_operation(
  p_worker_id text,
  p_job_id bigint,
  p_operation_id text,
  p_operation_type text,
  p_message_id bigint,
  p_result jsonb DEFAULT '{}'::jsonb,
  p_file_refs jsonb DEFAULT '[]'::jsonb
) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, vido AS $$
DECLARE j vido.bridge_jobs%ROWTYPE;
BEGIN
  SELECT * INTO j FROM vido.bridge_jobs WHERE id = p_job_id FOR UPDATE;
  IF NOT FOUND OR j.target_bot <> 'searchy' OR j.status <> 'delivering'
     OR j.lease_owner IS DISTINCT FROM p_worker_id
     OR j.lease_expires_at IS NULL OR j.lease_expires_at <= now() THEN
    RETURN false;
  END IF;

  INSERT INTO vido.delivery_operations(
    job_id, operation_id, operation_type, status, telegram_message_id, result_json
  ) VALUES (
    p_job_id, p_operation_id, p_operation_type, 'delivered', p_message_id, p_result
  ) ON CONFLICT (job_id, operation_id) DO UPDATE SET
    status = 'delivered', telegram_message_id = EXCLUDED.telegram_message_id,
    result_json = EXCLUDED.result_json, error_reason = NULL, updated_at = now();

  INSERT INTO vido.telegram_file_refs(
    content_key, variant_key, bot, send_kind, item_index, file_id, file_unique_id,
    plan_template
  )
  SELECT r.content_key, r.variant_key, 'searchy', r.send_kind,
         COALESCE(r.item_index, 0), r.file_id, r.file_unique_id,
         vido.redact_delivery_tokens(j.delivery_plan)
    FROM jsonb_to_recordset(
      CASE WHEN jsonb_typeof(p_file_refs) = 'array'
        THEN p_file_refs ELSE '[]'::jsonb END
    ) AS r(
      content_key text, variant_key text, send_kind text, item_index integer,
      file_id text, file_unique_id text
    )
   WHERE r.file_id IS NOT NULL
  ON CONFLICT (content_key, variant_key, bot, send_kind, item_index) DO UPDATE SET
    file_id = EXCLUDED.file_id, file_unique_id = EXCLUDED.file_unique_id,
    plan_template = EXCLUDED.plan_template,
    last_used_at = now(), invalidated_at = NULL;

  UPDATE vido.download_intents i SET
    origin_chat_id = j.target_chat_id,
    origin_message_id = p_message_id
  FROM jsonb_array_elements_text(
    CASE WHEN jsonb_typeof(p_result->'audio_token_hashes') = 'array'
      THEN p_result->'audio_token_hashes' ELSE '[]'::jsonb END
  ) token_hash
  WHERE token_hash.value ~ '^[0-9a-f]{64}$'
    AND i.token_hash = decode(token_hash.value, 'hex')
    AND i.owner_user_id = j.owner_user_id
    AND i.consumed_at IS NULL AND i.expires_at > now();
  RETURN true;
END; $$;

CREATE OR REPLACE FUNCTION vido.fail_searchy_operation(
  p_worker_id text,
  p_job_id bigint,
  p_operation_id text,
  p_operation_type text,
  p_error_reason text,
  p_delivery_unknown boolean DEFAULT false
) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, vido AS $$
DECLARE j vido.bridge_jobs%ROWTYPE;
DECLARE previous_status text;
DECLARE next_status text := CASE WHEN p_delivery_unknown THEN 'delivery_unknown' ELSE 'failed' END;
BEGIN
  SELECT * INTO j FROM vido.bridge_jobs WHERE id = p_job_id FOR UPDATE;
  IF NOT FOUND OR j.target_bot <> 'searchy' OR j.status <> 'delivering'
     OR j.lease_owner IS DISTINCT FROM p_worker_id
     OR j.lease_expires_at IS NULL OR j.lease_expires_at <= now() THEN
    RETURN false;
  END IF;

  SELECT status INTO previous_status FROM vido.delivery_operations
   WHERE job_id = p_job_id AND operation_id = p_operation_id FOR UPDATE;
  IF previous_status = 'delivered' THEN
    RETURN true;
  END IF;

  INSERT INTO vido.delivery_operations(job_id, operation_id, operation_type, status, error_reason)
  VALUES (p_job_id, p_operation_id, p_operation_type, next_status, p_error_reason)
  ON CONFLICT (job_id, operation_id) DO UPDATE SET
    status = CASE WHEN vido.delivery_operations.status = 'delivered'
                  THEN 'delivered' ELSE EXCLUDED.status END,
    error_reason = CASE WHEN vido.delivery_operations.status = 'delivered'
                        THEN vido.delivery_operations.error_reason ELSE EXCLUDED.error_reason END,
    updated_at = now();

  IF p_error_reason = 'invalid_file_id' THEN
    next_status := CASE WHEN j.attempts < 2 THEN 'queued' ELSE 'failed' END;
    UPDATE vido.bridge_jobs SET
      status = next_status, error_reason = p_error_reason,
      user_message_key = 'error.download_failed', retryable = j.attempts < 2,
      delivery_plan = NULL, artifact_id = NULL,
      lease_owner = NULL, lease_expires_at = NULL, updated_at = now(),
      status_notified_for = NULL, status_notified_at = NULL,
      notification_lease_owner = NULL, notification_lease_expires_at = NULL
    WHERE id = p_job_id AND status = 'delivering' AND lease_owner = p_worker_id;
  ELSE
    UPDATE vido.bridge_jobs SET
      status = next_status, error_reason = p_error_reason,
      source_url = CASE WHEN p_delivery_unknown THEN source_url ELSE NULL END,
      settings_snapshot = CASE WHEN p_delivery_unknown THEN settings_snapshot ELSE NULL END,
      delivery_plan = CASE WHEN p_delivery_unknown THEN delivery_plan ELSE NULL END,
      lease_owner = NULL, lease_expires_at = NULL, updated_at = now(),
      status_notified_for = NULL, status_notified_at = NULL,
      notification_lease_owner = NULL, notification_lease_expires_at = NULL
    WHERE id = p_job_id AND status = 'delivering' AND lease_owner = p_worker_id;
  END IF;

  UPDATE vido.artifact_leases SET
    released_at = CASE WHEN next_status = 'delivery_unknown' THEN released_at ELSE now() END,
    expires_at = CASE WHEN next_status = 'delivery_unknown'
      THEN LEAST(expires_at, now() + interval '30 minutes') ELSE expires_at END
  WHERE job_id = p_job_id AND released_at IS NULL;
  PERFORM pg_notify('vido_bridge', p_job_id::text || ':' || next_status);
  IF next_status <> 'delivery_unknown' THEN
    PERFORM pg_notify('vido_artifact_release', p_job_id::text);
  END IF;
  RETURN true;
END; $$;

CREATE OR REPLACE FUNCTION vido.finish_searchy_delivery(
  p_worker_id text,
  p_job_id bigint
) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, vido AS $$
DECLARE j vido.bridge_jobs%ROWTYPE;
BEGIN
  SELECT * INTO j FROM vido.bridge_jobs WHERE id = p_job_id FOR UPDATE;
  IF NOT FOUND OR j.target_bot <> 'searchy' OR j.status <> 'delivering'
     OR j.lease_owner IS DISTINCT FROM p_worker_id
     OR j.lease_expires_at IS NULL OR j.lease_expires_at <= now()
     OR jsonb_array_length(COALESCE(j.delivery_plan->'operations', '[]'::jsonb)) = 0
     OR EXISTS (
       SELECT 1 FROM jsonb_array_elements(j.delivery_plan->'operations') item
        WHERE NOT EXISTS (
          SELECT 1 FROM vido.delivery_operations o
           WHERE o.job_id = p_job_id
             AND o.operation_id = item->>'operation_id'
             AND o.status = 'delivered'
        )
     ) THEN
    RETURN false;
  END IF;

  UPDATE vido.bridge_jobs SET
    status = 'delivered', delivered_at = now(), updated_at = now(),
    source_url = NULL, settings_snapshot = NULL, delivery_plan = NULL,
    lease_owner = NULL, lease_expires_at = NULL
  WHERE id = p_job_id;
  UPDATE vido.artifact_leases SET released_at = now()
   WHERE job_id = p_job_id AND released_at IS NULL;
  PERFORM pg_notify('vido_bridge', p_job_id::text || ':delivered');
  PERFORM pg_notify('vido_artifact_release', p_job_id::text);
  RETURN true;
END; $$;

CREATE OR REPLACE FUNCTION vido.reject_searchy_delivery(
  p_worker_id text,
  p_job_id bigint,
  p_reason text DEFAULT 'invalid_delivery_plan'
) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, vido AS $$
BEGIN
  UPDATE vido.bridge_jobs SET
    status = 'failed', error_reason = p_reason,
    user_message_key = 'error.download_failed', retryable = false,
    source_url = NULL, settings_snapshot = NULL, delivery_plan = NULL,
    lease_owner = NULL, lease_expires_at = NULL, updated_at = now(),
    status_notified_for = NULL, status_notified_at = NULL,
    notification_lease_owner = NULL, notification_lease_expires_at = NULL
  WHERE id = p_job_id AND target_bot = 'searchy' AND status = 'delivering'
    AND lease_owner = p_worker_id AND lease_expires_at > now();
  IF NOT FOUND THEN RETURN false; END IF;
  UPDATE vido.artifact_leases SET released_at = now()
   WHERE job_id = p_job_id AND released_at IS NULL;
  PERFORM pg_notify('vido_bridge', p_job_id::text || ':failed');
  PERFORM pg_notify('vido_artifact_release', p_job_id::text);
  RETURN true;
END; $$;

CREATE OR REPLACE FUNCTION vido.claim_searchy_notification(
  p_worker_id text,
  p_lease_seconds integer DEFAULT 120
) RETURNS TABLE(
  job_id bigint,
  owner_user_id bigint,
  target_chat_id bigint,
  target_thread_id bigint,
  origin_message_id bigint,
  job_status text,
  user_message_key text,
  language text,
  retry_token text
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, vido, public AS $$
DECLARE claimed vido.bridge_jobs%ROWTYPE;
DECLARE raw_token text;
BEGIN
  SELECT j.* INTO claimed FROM vido.bridge_jobs j
   WHERE j.target_bot = 'searchy' AND j.status IN ('failed', 'delivery_unknown')
     AND j.status_notified_for IS DISTINCT FROM j.status
     AND (j.notification_lease_expires_at IS NULL OR j.notification_lease_expires_at < now())
   ORDER BY j.updated_at
   FOR UPDATE SKIP LOCKED LIMIT 1;
  IF NOT FOUND THEN RETURN; END IF;

  UPDATE vido.bridge_jobs SET
    notification_lease_owner = p_worker_id,
    notification_lease_expires_at = now() + make_interval(secs => GREATEST(30, LEAST(p_lease_seconds, 300)))
  WHERE id = claimed.id;

  IF claimed.status = 'delivery_unknown' THEN
    raw_token := rtrim(translate(encode(public.gen_random_bytes(24), 'base64'), '+/', '-_'), '=');
    INSERT INTO vido.delivery_retry_intents(
      token_hash, job_id, owner_user_id, chat_id, message_id, expires_at
    ) VALUES (
      public.digest(raw_token, 'sha256'), claimed.id, claimed.owner_user_id,
      claimed.target_chat_id, claimed.origin_message_id, now() + interval '30 minutes'
    );
  END IF;

  RETURN QUERY SELECT claimed.id, claimed.owner_user_id, claimed.target_chat_id,
    claimed.target_thread_id, claimed.origin_message_id, claimed.status,
    COALESCE(claimed.user_message_key, 'error.download_failed'),
    core.effective_language(claimed.owner_user_id, NULL, 'user'), raw_token;
END; $$;

CREATE OR REPLACE FUNCTION vido.ack_searchy_notification(
  p_worker_id text,
  p_job_id bigint,
  p_status text
) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, vido AS $$
BEGIN
  UPDATE vido.bridge_jobs SET
    status_notified_for = status, status_notified_at = now(),
    notification_lease_owner = NULL, notification_lease_expires_at = NULL
  WHERE id = p_job_id AND target_bot = 'searchy' AND status = p_status
    AND notification_lease_owner = p_worker_id
    AND notification_lease_expires_at > now();
  RETURN FOUND;
END; $$;

CREATE OR REPLACE FUNCTION vido.enqueue_searchy_retry_job(
  p_token_hash bytea,
  p_actor_user_id bigint,
  p_chat_id bigint,
  p_thread_id bigint,
  p_message_id bigint,
  p_request_key text
) RETURNS TABLE(job_id bigint, job_status text, activity_stage text)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, vido AS $$
DECLARE r vido.delivery_retry_intents%ROWTYPE;
DECLARE j vido.bridge_jobs%ROWTYPE;
DECLARE has_active_artifact boolean;
BEGIN
  SELECT * INTO r FROM vido.delivery_retry_intents
   WHERE token_hash = p_token_hash FOR UPDATE;
  IF NOT FOUND OR r.expires_at <= now() THEN
    RAISE EXCEPTION 'intent_expired' USING ERRCODE = 'P0001';
  END IF;
  IF r.owner_user_id <> p_actor_user_id THEN
    RAISE EXCEPTION 'intent_not_owner' USING ERRCODE = '42501';
  END IF;
  IF r.chat_id <> p_chat_id OR r.message_id <> p_message_id THEN
    RAISE EXCEPTION 'intent_wrong_context' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO j FROM vido.bridge_jobs WHERE id = r.job_id FOR UPDATE;
  IF r.consumed_at IS NOT NULL THEN
    IF NOT FOUND OR j.target_bot <> 'searchy' THEN
      RAISE EXCEPTION 'intent_expired' USING ERRCODE = 'P0001';
    END IF;
    RETURN QUERY SELECT j.id, j.status, j.activity_stage;
    RETURN;
  END IF;
  IF NOT FOUND OR j.target_bot <> 'searchy' OR j.status <> 'delivery_unknown' THEN
    RAISE EXCEPTION 'intent_expired' USING ERRCODE = 'P0001';
  END IF;
  SELECT EXISTS (
    SELECT 1 FROM vido.artifact_leases l
     WHERE l.job_id = j.id AND l.released_at IS NULL AND l.expires_at > now()
  ) INTO has_active_artifact;

  DELETE FROM vido.delivery_operations o
   WHERE o.job_id = j.id AND o.status <> 'delivered';
  UPDATE vido.bridge_jobs SET
    status = CASE WHEN has_active_artifact THEN 'ready' ELSE 'queued' END,
    delivery_plan = CASE WHEN has_active_artifact THEN delivery_plan ELSE NULL END,
    artifact_id = CASE WHEN has_active_artifact THEN artifact_id ELSE NULL END,
    attempts = CASE WHEN has_active_artifact THEN attempts ELSE 0 END,
    target_thread_id = p_thread_id, error_reason = NULL, retryable = false,
    lease_owner = NULL, lease_expires_at = NULL, updated_at = now(),
    status_notified_for = NULL, status_notified_at = NULL,
    notification_lease_owner = NULL, notification_lease_expires_at = NULL
  WHERE id = j.id;
  UPDATE vido.artifact_leases l SET released_at = now()
   WHERE l.job_id = j.id AND l.released_at IS NULL AND l.expires_at <= now();
  UPDATE vido.delivery_retry_intents SET
    consumed_at = now(), consumed_request_key = p_request_key
   WHERE token_hash = p_token_hash;
  PERFORM pg_notify('vido_bridge', j.id::text || ':' || CASE WHEN has_active_artifact THEN 'ready' ELSE 'queued' END);
  RETURN QUERY SELECT j.id,
    CASE WHEN has_active_artifact THEN 'ready'::text ELSE 'queued'::text END,
    j.activity_stage;
END; $$;

DELETE FROM vido.delivery_retry_intents WHERE expires_at <= now();

REVOKE ALL ON FUNCTION vido.begin_searchy_operation(text,bigint,text,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION vido.renew_searchy_delivery(text,bigint,integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION vido.reject_searchy_delivery(text,bigint,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION vido.claim_searchy_notification(text,integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION vido.ack_searchy_notification(text,bigint,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION vido.enqueue_searchy_retry_job(bytea,bigint,bigint,bigint,bigint,text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION vido.begin_searchy_operation(text,bigint,text,text) TO searchy_core;
GRANT EXECUTE ON FUNCTION vido.renew_searchy_delivery(text,bigint,integer) TO searchy_core;
GRANT EXECUTE ON FUNCTION vido.reject_searchy_delivery(text,bigint,text) TO searchy_core;
GRANT EXECUTE ON FUNCTION vido.claim_searchy_notification(text,integer) TO searchy_core;
GRANT EXECUTE ON FUNCTION vido.ack_searchy_notification(text,bigint,text) TO searchy_core;
GRANT EXECUTE ON FUNCTION vido.enqueue_searchy_retry_job(bytea,bigint,bigint,bigint,bigint,text) TO searchy_core;

REVOKE ALL ON ALL TABLES IN SCHEMA vido FROM searchy_core;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA vido FROM searchy_core;
