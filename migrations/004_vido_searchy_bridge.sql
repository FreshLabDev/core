-- ==========================================================================
-- core :: 004 — Vido/Searchy durable media bridge
--
-- Searchy can create owner-bound download intents and deliver plans produced
-- by Vido, but it never receives the selected source URL or Vido settings.
-- All Searchy access is through the SECURITY DEFINER functions at the end of
-- this migration. The raw tables remain private to vido_core.
-- ==========================================================================

BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

CREATE SCHEMA IF NOT EXISTS vido;

CREATE TABLE IF NOT EXISTS vido.download_intents (
  token_hash          bytea PRIMARY KEY CHECK (octet_length(token_hash) = 32),
  owner_user_id       bigint NOT NULL REFERENCES core.person(telegram_user_id),
  kind                text NOT NULL CHECK (kind IN ('video', 'audio')),
  delivery_mode       text NOT NULL CHECK (delivery_mode IN ('searchy_chat', 'vido_dm')),
  source_url          text,
  platform            text NOT NULL DEFAULT 'other',
  source_surface      text NOT NULL
    CHECK (source_surface IN (
      'searchy_inline', 'searchy_chat', 'searchy_audio',
      'vido_bridge_audio', 'vido_direct'
    )),
  origin_chat_id      bigint REFERENCES core.chat(chat_id),
  origin_message_id   bigint,
  username            text,
  first_name          text,
  last_name           text,
  tg_language_code    text,
  parent_job_id       bigint,
  created_at          timestamptz NOT NULL DEFAULT now(),
  expires_at          timestamptz NOT NULL,
  consumed_at         timestamptz,
  job_id              bigint,
  CHECK (expires_at > created_at)
);
CREATE INDEX IF NOT EXISTS ix_download_intents_expires
  ON vido.download_intents (expires_at);
CREATE INDEX IF NOT EXISTS ix_download_intents_owner
  ON vido.download_intents (owner_user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS vido.bridge_jobs (
  id                   bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  intent_token_hash    bytea NOT NULL UNIQUE REFERENCES vido.download_intents(token_hash),
  request_key          text NOT NULL UNIQUE,
  owner_user_id        bigint NOT NULL REFERENCES core.person(telegram_user_id),
  kind                 text NOT NULL CHECK (kind IN ('video', 'audio')),
  target_bot           text NOT NULL CHECK (target_bot IN ('searchy', 'vido')),
  target_chat_id       bigint NOT NULL REFERENCES core.chat(chat_id),
  target_thread_id     bigint,
  origin_message_id    bigint,
  source_url           text,
  platform             text NOT NULL DEFAULT 'other',
  status               text NOT NULL DEFAULT 'queued'
    CHECK (status IN ('queued', 'processing', 'ready', 'delivering',
                      'delivered', 'failed', 'delivery_unknown')),
  activity_stage       text NOT NULL DEFAULT 'preparing'
    CHECK (activity_stage IN ('preparing', 'downloading', 'uploading_video',
                              'uploading_photo', 'uploading_audio',
                              'uploading_document')),
  settings_snapshot    jsonb,
  delivery_plan        jsonb,
  artifact_id          bigint,
  attempts             integer NOT NULL DEFAULT 0 CHECK (attempts BETWEEN 0 AND 3),
  lease_owner          text,
  lease_expires_at     timestamptz,
  error_reason         text,
  user_message_key     text,
  retryable            boolean NOT NULL DEFAULT false,
  next_attempt_at       timestamptz NOT NULL DEFAULT now(),
  created_at           timestamptz NOT NULL DEFAULT now(),
  updated_at           timestamptz NOT NULL DEFAULT now(),
  started_at           timestamptz,
  ready_at             timestamptz,
  delivered_at         timestamptz,
  cleanup_after        timestamptz NOT NULL DEFAULT (now() + interval '30 days')
);
ALTER TABLE vido.bridge_jobs
  ADD COLUMN IF NOT EXISTS next_attempt_at timestamptz NOT NULL DEFAULT now();

DO $$ BEGIN
  ALTER TABLE vido.download_intents
    ADD CONSTRAINT download_intents_source_surface_check
    CHECK (source_surface IN (
      'searchy_inline', 'searchy_chat', 'searchy_audio',
      'vido_bridge_audio', 'vido_direct'
    ));
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
CREATE INDEX IF NOT EXISTS ix_bridge_jobs_claim
  ON vido.bridge_jobs (status, lease_expires_at, created_at);
CREATE INDEX IF NOT EXISTS ix_bridge_jobs_runnable
  ON vido.bridge_jobs (status, next_attempt_at, created_at);
CREATE INDEX IF NOT EXISTS ix_bridge_jobs_owner
  ON vido.bridge_jobs (owner_user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS ix_bridge_jobs_cleanup
  ON vido.bridge_jobs (cleanup_after);

ALTER TABLE vido.download_intents
  DROP CONSTRAINT IF EXISTS download_intents_parent_job_id_fkey;
ALTER TABLE vido.download_intents
  ADD CONSTRAINT download_intents_parent_job_id_fkey
  FOREIGN KEY (parent_job_id) REFERENCES vido.bridge_jobs(id) ON DELETE SET NULL;
ALTER TABLE vido.download_intents
  DROP CONSTRAINT IF EXISTS download_intents_job_id_fkey;
ALTER TABLE vido.download_intents
  ADD CONSTRAINT download_intents_job_id_fkey
  FOREIGN KEY (job_id) REFERENCES vido.bridge_jobs(id) ON DELETE SET NULL;

CREATE TABLE IF NOT EXISTS vido.shared_artifacts (
  id                   bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  cache_key            text NOT NULL UNIQUE,
  state                text NOT NULL DEFAULT 'building'
    CHECK (state IN ('building', 'ready', 'deleting', 'deleted', 'failed')),
  root_path            text,
  manifest             jsonb,
  total_size           bigint NOT NULL DEFAULT 0 CHECK (total_size >= 0),
  producer_job_id      bigint REFERENCES vido.bridge_jobs(id) ON DELETE SET NULL,
  created_at           timestamptz NOT NULL DEFAULT now(),
  updated_at           timestamptz NOT NULL DEFAULT now(),
  ready_at             timestamptz,
  delete_after         timestamptz,
  deleted_at           timestamptz,
  error_reason         text
);
CREATE INDEX IF NOT EXISTS ix_shared_artifacts_state
  ON vido.shared_artifacts (state, delete_after);

ALTER TABLE vido.bridge_jobs
  DROP CONSTRAINT IF EXISTS bridge_jobs_artifact_id_fkey;
ALTER TABLE vido.bridge_jobs
  ADD CONSTRAINT bridge_jobs_artifact_id_fkey
  FOREIGN KEY (artifact_id) REFERENCES vido.shared_artifacts(id) ON DELETE SET NULL;

CREATE TABLE IF NOT EXISTS vido.artifact_leases (
  artifact_id          bigint NOT NULL REFERENCES vido.shared_artifacts(id) ON DELETE CASCADE,
  job_id               bigint NOT NULL REFERENCES vido.bridge_jobs(id) ON DELETE CASCADE,
  consumer_bot         text NOT NULL CHECK (consumer_bot IN ('searchy', 'vido')),
  acquired_at          timestamptz NOT NULL DEFAULT now(),
  expires_at           timestamptz NOT NULL,
  released_at          timestamptz,
  PRIMARY KEY (artifact_id, job_id)
);
CREATE INDEX IF NOT EXISTS ix_artifact_leases_active
  ON vido.artifact_leases (artifact_id, expires_at)
  WHERE released_at IS NULL;

CREATE TABLE IF NOT EXISTS vido.delivery_operations (
  job_id               bigint NOT NULL REFERENCES vido.bridge_jobs(id) ON DELETE CASCADE,
  operation_id         text NOT NULL,
  operation_type       text NOT NULL
    CHECK (operation_type IN ('video', 'photo', 'audio', 'document', 'media_group', 'text')),
  status               text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'delivered', 'failed', 'delivery_unknown')),
  telegram_message_id  bigint,
  result_json          jsonb,
  error_reason         text,
  updated_at           timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (job_id, operation_id)
);

CREATE TABLE IF NOT EXISTS vido.telegram_file_refs (
  id                   bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  content_key          text NOT NULL,
  variant_key          text NOT NULL,
  bot                  text NOT NULL CHECK (bot IN ('searchy', 'vido')),
  send_kind            text NOT NULL
    CHECK (send_kind IN ('video', 'photo', 'audio', 'document')),
  item_index           integer NOT NULL DEFAULT 0 CHECK (item_index >= 0),
  file_id              text NOT NULL,
  file_unique_id       text,
  plan_template        jsonb,
  created_at           timestamptz NOT NULL DEFAULT now(),
  last_used_at         timestamptz NOT NULL DEFAULT now(),
  invalidated_at       timestamptz,
  UNIQUE (content_key, variant_key, bot, send_kind, item_index)
);
CREATE INDEX IF NOT EXISTS ix_telegram_file_refs_active
  ON vido.telegram_file_refs (content_key, variant_key, bot)
  WHERE invalidated_at IS NULL;
CREATE INDEX IF NOT EXISTS ix_telegram_file_refs_file_id
  ON vido.telegram_file_refs (bot, file_id)
  WHERE invalidated_at IS NULL;

-- The vido runtime owns the durable queue/cache data. Searchy stays function-only.
GRANT USAGE ON SCHEMA vido TO vido_core, searchy_core;
GRANT SELECT, INSERT, UPDATE, DELETE ON
  vido.download_intents, vido.bridge_jobs, vido.shared_artifacts,
  vido.artifact_leases, vido.delivery_operations, vido.telegram_file_refs
  TO vido_core;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA vido TO vido_core;

CREATE OR REPLACE FUNCTION vido.create_download_intent(
  p_token_hash bytea,
  p_owner_user_id bigint,
  p_kind text,
  p_delivery_mode text,
  p_source_url text,
  p_platform text,
  p_source_surface text,
  p_expires_at timestamptz,
  p_origin_chat_id bigint DEFAULT NULL,
  p_username text DEFAULT NULL,
  p_first_name text DEFAULT NULL,
  p_last_name text DEFAULT NULL,
  p_tg_language_code text DEFAULT NULL,
  p_parent_job_id bigint DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, core, vido AS $$
BEGIN
  IF octet_length(p_token_hash) <> 32 OR p_source_url IS NULL OR p_source_url = '' THEN
    RAISE EXCEPTION 'invalid_intent' USING ERRCODE = '22023';
  END IF;
  IF p_kind NOT IN ('video', 'audio')
     OR p_delivery_mode NOT IN ('searchy_chat', 'vido_dm')
     OR p_expires_at <= now() THEN
    RAISE EXCEPTION 'invalid_intent' USING ERRCODE = '22023';
  END IF;

  PERFORM core.touch(
    'searchy', p_owner_user_id, p_username, p_first_name, p_last_name,
    p_tg_language_code, p_origin_chat_id, NULL, NULL, NULL, false, now()
  );

  INSERT INTO vido.download_intents(
    token_hash, owner_user_id, kind, delivery_mode, source_url, platform,
    source_surface, origin_chat_id, username, first_name, last_name,
    tg_language_code, parent_job_id, expires_at
  ) VALUES (
    p_token_hash, p_owner_user_id, p_kind, p_delivery_mode, p_source_url,
    COALESCE(NULLIF(p_platform, ''), 'other'), p_source_surface,
    p_origin_chat_id, p_username, p_first_name, p_last_name,
    p_tg_language_code, p_parent_job_id, p_expires_at
  );
END; $$;

CREATE OR REPLACE FUNCTION vido.bind_intent_message(
  p_token_hash bytea,
  p_owner_user_id bigint,
  p_chat_id bigint,
  p_message_id bigint
) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, vido AS $$
BEGIN
  UPDATE vido.download_intents
     SET origin_message_id = p_message_id
   WHERE token_hash = p_token_hash
     AND owner_user_id = p_owner_user_id
     AND delivery_mode = 'searchy_chat'
     AND origin_chat_id = p_chat_id
     AND expires_at > now()
     AND consumed_at IS NULL;
  RETURN FOUND;
END; $$;

CREATE OR REPLACE FUNCTION vido.enqueue_searchy_job(
  p_token_hash bytea,
  p_actor_user_id bigint,
  p_chat_id bigint,
  p_thread_id bigint,
  p_message_id bigint,
  p_request_key text
) RETURNS TABLE(job_id bigint, job_status text, activity_stage text)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, vido AS $$
DECLARE i vido.download_intents%ROWTYPE;
DECLARE new_job_id bigint;
BEGIN
  SELECT * INTO i FROM vido.download_intents
   WHERE token_hash = p_token_hash FOR UPDATE;
  IF NOT FOUND OR i.expires_at <= now() THEN
    RAISE EXCEPTION 'intent_expired' USING ERRCODE = 'P0001';
  END IF;
  IF i.owner_user_id <> p_actor_user_id THEN
    RAISE EXCEPTION 'intent_not_owner' USING ERRCODE = '42501';
  END IF;
  IF i.delivery_mode <> 'searchy_chat' OR i.origin_chat_id IS DISTINCT FROM p_chat_id
     OR (i.origin_message_id IS NOT NULL AND i.origin_message_id <> p_message_id) THEN
    RAISE EXCEPTION 'intent_wrong_context' USING ERRCODE = '42501';
  END IF;

  IF i.job_id IS NOT NULL THEN
	IF p_request_key LIKE 'retry:%' THEN
		UPDATE vido.bridge_jobs j SET
		  status = CASE WHEN j.status = 'delivery_unknown' AND EXISTS (
		                  SELECT 1 FROM vido.artifact_leases active_lease
		                   WHERE active_lease.job_id = j.id
		                     AND active_lease.released_at IS NULL
		                     AND active_lease.expires_at > now()
		                ) THEN 'ready'
		                WHEN j.status = 'delivery_unknown' THEN 'queued' ELSE j.status END,
		  error_reason = CASE WHEN j.status = 'delivery_unknown' THEN NULL ELSE j.error_reason END,
		  delivery_plan = CASE WHEN j.status = 'delivery_unknown' AND NOT EXISTS (
		                         SELECT 1 FROM vido.artifact_leases active_lease
		                          WHERE active_lease.job_id = j.id
		                            AND active_lease.released_at IS NULL
		                            AND active_lease.expires_at > now()
		                       )
		                       THEN NULL ELSE j.delivery_plan END,
		  artifact_id = CASE WHEN j.status = 'delivery_unknown' AND NOT EXISTS (
		                       SELECT 1 FROM vido.artifact_leases active_lease
		                        WHERE active_lease.job_id = j.id
		                          AND active_lease.released_at IS NULL
		                          AND active_lease.expires_at > now()
		                     )
		                     THEN NULL ELSE j.artifact_id END,
		  attempts = CASE WHEN j.status = 'delivery_unknown' AND NOT EXISTS (
		                      SELECT 1 FROM vido.artifact_leases active_lease
		                       WHERE active_lease.job_id = j.id
		                         AND active_lease.released_at IS NULL
		                         AND active_lease.expires_at > now()
		                    )
		                  THEN 0 ELSE j.attempts END,
		  lease_owner = CASE WHEN j.status = 'delivery_unknown' THEN NULL ELSE j.lease_owner END,
		  lease_expires_at = CASE WHEN j.status = 'delivery_unknown' THEN NULL ELSE j.lease_expires_at END,
		  updated_at = now()
		WHERE j.id = i.job_id AND j.target_bot = 'searchy';
		UPDATE vido.artifact_leases l SET released_at = now()
		 WHERE l.job_id = i.job_id AND l.released_at IS NULL AND l.expires_at <= now();
		PERFORM pg_notify('vido_bridge', i.job_id::text || ':ready');
	END IF;
    RETURN QUERY SELECT j.id, j.status, j.activity_stage
      FROM vido.bridge_jobs j WHERE j.id = i.job_id;
    RETURN;
  END IF;

  INSERT INTO vido.bridge_jobs(
    intent_token_hash, request_key, owner_user_id, kind, target_bot,
    target_chat_id, target_thread_id, origin_message_id, source_url, platform
  ) VALUES (
    p_token_hash, p_request_key, i.owner_user_id, i.kind, 'searchy',
    p_chat_id, p_thread_id, p_message_id, i.source_url, i.platform
  ) RETURNING id INTO new_job_id;

  UPDATE vido.download_intents
     SET consumed_at = now(), job_id = new_job_id, source_url = NULL
   WHERE token_hash = p_token_hash;
  PERFORM pg_notify('vido_bridge', new_job_id::text || ':queued');
  RETURN QUERY SELECT new_job_id, 'queued'::text, 'preparing'::text;
END; $$;

CREATE OR REPLACE FUNCTION vido.enqueue_searchy_audio_job(
  p_token_hash bytea,
  p_actor_user_id bigint,
  p_chat_id bigint,
  p_thread_id bigint,
  p_message_id bigint,
  p_request_key text
) RETURNS TABLE(job_id bigint, job_status text, activity_stage text)
LANGUAGE sql SECURITY DEFINER
SET search_path = pg_catalog, vido AS $$
  SELECT * FROM vido.enqueue_searchy_job(
    p_token_hash, p_actor_user_id, p_chat_id, p_thread_id,
    p_message_id, p_request_key
  );
$$;

CREATE OR REPLACE FUNCTION vido.get_searchy_job_stage(p_job_id bigint)
RETURNS TABLE(
  job_status text,
  activity_stage text,
  error_reason text,
  user_message_key text,
  retryable boolean
)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, vido AS $$
  SELECT status, activity_stage, error_reason, user_message_key, retryable
    FROM vido.bridge_jobs
   WHERE id = p_job_id AND target_bot = 'searchy';
$$;

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
  RETURN QUERY
  WITH candidate AS (
    SELECT id FROM vido.bridge_jobs
     WHERE target_bot = 'searchy'
       AND status IN ('ready', 'delivering')
       AND (lease_expires_at IS NULL OR lease_expires_at < now())
     ORDER BY ready_at NULLS LAST, created_at
     FOR UPDATE SKIP LOCKED
     LIMIT 1
  )
  UPDATE vido.bridge_jobs j
     SET status = 'delivering', lease_owner = p_worker_id,
         lease_expires_at = now() + make_interval(secs => GREATEST(30, LEAST(p_lease_seconds, 900))),
         updated_at = now()
    FROM candidate c
   WHERE j.id = c.id
  RETURNING j.id, j.owner_user_id, j.target_chat_id, j.target_thread_id,
            j.origin_message_id, j.delivery_plan,
            ARRAY(
              SELECT o.operation_id
                FROM vido.delivery_operations o
               WHERE o.job_id = j.id AND o.status = 'delivered'
               ORDER BY o.operation_id
            );
END; $$;

CREATE OR REPLACE FUNCTION vido.redact_delivery_tokens(p_value jsonb)
RETURNS jsonb
LANGUAGE plpgsql IMMUTABLE
SET search_path = pg_catalog, vido AS $$
DECLARE result jsonb;
DECLARE item record;
BEGIN
  CASE jsonb_typeof(p_value)
    WHEN 'object' THEN
      result := '{}'::jsonb;
      FOR item IN SELECT key, value FROM jsonb_each(p_value)
      LOOP
        result := result || jsonb_build_object(
          item.key,
          CASE WHEN item.key = 'token'
            THEN to_jsonb(repeat('_', 32))
            ELSE vido.redact_delivery_tokens(item.value)
          END
        );
      END LOOP;
      RETURN result;
    WHEN 'array' THEN
      SELECT COALESCE(jsonb_agg(vido.redact_delivery_tokens(value)), '[]'::jsonb)
        INTO result FROM jsonb_array_elements(p_value);
      RETURN result;
    ELSE
      RETURN p_value;
  END CASE;
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
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM vido.bridge_jobs
     WHERE id = p_job_id AND target_bot = 'searchy'
       AND status = 'delivering' AND lease_owner = p_worker_id
       AND lease_expires_at > now()
  ) THEN
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
         (SELECT vido.redact_delivery_tokens(delivery_plan)
            FROM vido.bridge_jobs WHERE id = p_job_id)
    FROM jsonb_to_recordset(COALESCE(p_file_refs, '[]'::jsonb)) AS r(
      content_key text, variant_key text, send_kind text, item_index integer,
      file_id text, file_unique_id text
    )
   WHERE r.file_id IS NOT NULL
  ON CONFLICT (content_key, variant_key, bot, send_kind, item_index) DO UPDATE SET
    file_id = EXCLUDED.file_id, file_unique_id = EXCLUDED.file_unique_id,
    plan_template = EXCLUDED.plan_template,
    last_used_at = now(), invalidated_at = NULL;
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
DECLARE next_status text := CASE WHEN p_delivery_unknown THEN 'delivery_unknown' ELSE 'failed' END;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM vido.bridge_jobs
     WHERE id = p_job_id AND target_bot = 'searchy'
       AND status = 'delivering' AND lease_owner = p_worker_id
  ) THEN
    RETURN false;
  END IF;
  INSERT INTO vido.delivery_operations(job_id, operation_id, operation_type, status, error_reason)
  VALUES (p_job_id, p_operation_id, p_operation_type, next_status, p_error_reason)
  ON CONFLICT (job_id, operation_id) DO UPDATE SET
    status = EXCLUDED.status, error_reason = EXCLUDED.error_reason, updated_at = now();

  IF p_error_reason = 'invalid_file_id' THEN
    UPDATE vido.bridge_jobs SET
      status = CASE WHEN attempts < 2 THEN 'queued' ELSE 'failed' END,
      error_reason = p_error_reason,
      user_message_key = 'error.download_failed',
      retryable = attempts < 2,
      delivery_plan = NULL,
      artifact_id = NULL,
      lease_owner = NULL,
      lease_expires_at = NULL,
      updated_at = now()
    WHERE id = p_job_id
    RETURNING status INTO next_status;
    UPDATE vido.artifact_leases SET released_at = now()
     WHERE job_id = p_job_id AND released_at IS NULL;
    PERFORM pg_notify('vido_bridge', p_job_id::text || ':' || next_status);
    PERFORM pg_notify('vido_artifact_release', p_job_id::text);
    RETURN true;
  END IF;

  UPDATE vido.bridge_jobs SET
    status = next_status,
    error_reason = p_error_reason,
		source_url = CASE WHEN p_delivery_unknown THEN source_url ELSE NULL END,
		settings_snapshot = CASE WHEN p_delivery_unknown THEN settings_snapshot ELSE NULL END,
		delivery_plan = CASE WHEN p_delivery_unknown THEN delivery_plan ELSE NULL END,
    lease_owner = NULL,
    lease_expires_at = NULL,
    updated_at = now()
  WHERE id = p_job_id;
  UPDATE vido.artifact_leases SET
    released_at = CASE WHEN p_delivery_unknown THEN released_at ELSE now() END,
    expires_at = CASE WHEN p_delivery_unknown
      THEN LEAST(expires_at, now() + interval '30 minutes') ELSE expires_at END
  WHERE job_id = p_job_id AND released_at IS NULL;
  PERFORM pg_notify('vido_bridge', p_job_id::text || ':' || next_status);
  RETURN true;
END; $$;

CREATE OR REPLACE FUNCTION vido.finish_searchy_delivery(
  p_worker_id text,
  p_job_id bigint
) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, vido AS $$
BEGIN
  UPDATE vido.bridge_jobs SET
    status = 'delivered', delivered_at = now(), updated_at = now(),
    source_url = NULL, settings_snapshot = NULL, delivery_plan = NULL,
    lease_owner = NULL, lease_expires_at = NULL
  WHERE id = p_job_id AND target_bot = 'searchy'
    AND status = 'delivering' AND lease_owner = p_worker_id;
  IF NOT FOUND THEN RETURN false; END IF;

  UPDATE vido.artifact_leases
     SET released_at = now()
   WHERE job_id = p_job_id AND released_at IS NULL;
  PERFORM pg_notify('vido_bridge', p_job_id::text || ':delivered');
  PERFORM pg_notify('vido_artifact_release', p_job_id::text);
  RETURN true;
END; $$;

CREATE OR REPLACE FUNCTION vido.invalidate_searchy_file_ref(p_file_id text)
RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, vido AS $$
BEGIN
  UPDATE vido.telegram_file_refs
     SET invalidated_at = now()
   WHERE bot = 'searchy' AND file_id = p_file_id AND invalidated_at IS NULL;
  RETURN FOUND;
END; $$;

REVOKE ALL ON ALL TABLES IN SCHEMA vido FROM searchy_core;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA vido FROM searchy_core;

REVOKE ALL ON FUNCTION vido.create_download_intent(bytea,bigint,text,text,text,text,text,timestamptz,bigint,text,text,text,text,bigint) FROM PUBLIC;
REVOKE ALL ON FUNCTION vido.bind_intent_message(bytea,bigint,bigint,bigint) FROM PUBLIC;
REVOKE ALL ON FUNCTION vido.enqueue_searchy_job(bytea,bigint,bigint,bigint,bigint,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION vido.enqueue_searchy_audio_job(bytea,bigint,bigint,bigint,bigint,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION vido.get_searchy_job_stage(bigint) FROM PUBLIC;
REVOKE ALL ON FUNCTION vido.claim_searchy_delivery(text,integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION vido.redact_delivery_tokens(jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION vido.ack_searchy_operation(text,bigint,text,text,bigint,jsonb,jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION vido.fail_searchy_operation(text,bigint,text,text,text,boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION vido.finish_searchy_delivery(text,bigint) FROM PUBLIC;
REVOKE ALL ON FUNCTION vido.invalidate_searchy_file_ref(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION vido.create_download_intent(bytea,bigint,text,text,text,text,text,timestamptz,bigint,text,text,text,text,bigint) TO searchy_core, vido_core;
GRANT EXECUTE ON FUNCTION vido.bind_intent_message(bytea,bigint,bigint,bigint) TO searchy_core;
GRANT EXECUTE ON FUNCTION vido.enqueue_searchy_job(bytea,bigint,bigint,bigint,bigint,text) TO searchy_core;
GRANT EXECUTE ON FUNCTION vido.enqueue_searchy_audio_job(bytea,bigint,bigint,bigint,bigint,text) TO searchy_core;
GRANT EXECUTE ON FUNCTION vido.get_searchy_job_stage(bigint) TO searchy_core;
GRANT EXECUTE ON FUNCTION vido.claim_searchy_delivery(text,integer) TO searchy_core;
GRANT EXECUTE ON FUNCTION vido.ack_searchy_operation(text,bigint,text,text,bigint,jsonb,jsonb) TO searchy_core;
GRANT EXECUTE ON FUNCTION vido.fail_searchy_operation(text,bigint,text,text,text,boolean) TO searchy_core;
GRANT EXECUTE ON FUNCTION vido.finish_searchy_delivery(text,bigint) TO searchy_core;
GRANT EXECUTE ON FUNCTION vido.invalidate_searchy_file_ref(text) TO searchy_core;

COMMIT;
