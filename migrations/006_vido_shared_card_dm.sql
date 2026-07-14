-- ============================================================================
-- core :: 006 — personal Vido DM downloads from shared Searchy cards
--
-- A Searchy result card remains owner-deliverable in its original chat. Other
-- users may derive a short-lived, owner-bound Vido DM intent without Searchy
-- ever reading the source URL. The original card/message binding is mandatory
-- so copied callback data cannot be replayed from another Telegram message.
-- ============================================================================

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

ALTER TABLE vido.download_intents
  DROP CONSTRAINT IF EXISTS download_intents_source_surface_check;
ALTER TABLE vido.download_intents
  ADD CONSTRAINT download_intents_source_surface_check
  CHECK (source_surface IN (
    'searchy_inline', 'searchy_chat', 'searchy_shared', 'searchy_audio',
    'vido_bridge_audio', 'vido_direct'
  ));

-- Searchy chat cards are shareable for their original six-hour lifetime. Keep
-- their protected URL after the owner's job is created; Vido's record sweeper
-- clears it as soon as the card expires. Other intent types retain the existing
-- consume-and-clear behavior.
CREATE OR REPLACE FUNCTION vido.preserve_searchy_card_source()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, vido AS $$
BEGIN
  IF OLD.delivery_mode = 'searchy_chat'
     AND OLD.source_surface = 'searchy_chat'
     AND OLD.origin_chat_id < 0
     AND OLD.source_url IS NOT NULL
     AND OLD.expires_at > now()
     AND NEW.job_id IS NOT NULL
     AND NEW.source_url IS NULL THEN
    NEW.source_url := OLD.source_url;
  END IF;
  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS preserve_searchy_card_source
  ON vido.download_intents;
CREATE TRIGGER preserve_searchy_card_source
BEFORE UPDATE OF source_url, job_id ON vido.download_intents
FOR EACH ROW EXECUTE FUNCTION vido.preserve_searchy_card_source();

CREATE OR REPLACE FUNCTION vido.create_shared_vido_intent(
  p_source_token_hash bytea,
  p_new_token_hash bytea,
  p_actor_user_id bigint,
  p_chat_id bigint,
  p_message_id bigint,
  p_username text DEFAULT NULL,
  p_first_name text DEFAULT NULL,
  p_last_name text DEFAULT NULL,
  p_tg_language_code text DEFAULT NULL
) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, core, vido AS $$
DECLARE source_intent vido.download_intents%ROWTYPE;
BEGIN
  IF p_source_token_hash IS NULL
     OR p_new_token_hash IS NULL
     OR octet_length(p_source_token_hash) <> 32
     OR octet_length(p_new_token_hash) <> 32
     OR p_source_token_hash = p_new_token_hash
     OR p_actor_user_id IS NULL
     OR p_actor_user_id <= 0
     OR p_chat_id IS NULL
     OR p_chat_id >= 0
     OR p_message_id IS NULL
     OR p_message_id <= 0 THEN
    RAISE EXCEPTION 'invalid_intent' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO source_intent
    FROM vido.download_intents
   WHERE token_hash = p_source_token_hash
   FOR UPDATE;

  IF NOT FOUND OR source_intent.expires_at <= now()
     OR source_intent.source_url IS NULL THEN
    RAISE EXCEPTION 'intent_expired' USING ERRCODE = 'P0001';
  END IF;
  IF source_intent.kind <> 'video'
     OR source_intent.delivery_mode <> 'searchy_chat'
     OR source_intent.source_surface <> 'searchy_chat'
     OR source_intent.origin_chat_id IS DISTINCT FROM p_chat_id
     OR source_intent.origin_message_id IS NULL
     OR source_intent.origin_message_id IS DISTINCT FROM p_message_id THEN
    RAISE EXCEPTION 'intent_wrong_context' USING ERRCODE = '42501';
  END IF;

  PERFORM core.touch(
    'searchy', p_actor_user_id, p_username, p_first_name, p_last_name,
    p_tg_language_code, p_chat_id, NULL, NULL, NULL, false, now()
  );

  INSERT INTO vido.download_intents(
    token_hash, owner_user_id, kind, delivery_mode, source_url, platform,
    source_surface, origin_chat_id, origin_message_id, username, first_name,
    last_name, tg_language_code, expires_at
  ) VALUES (
    p_new_token_hash, p_actor_user_id, 'video', 'vido_dm',
    source_intent.source_url, source_intent.platform, 'searchy_shared',
    p_chat_id, p_message_id, p_username, p_first_name, p_last_name,
    p_tg_language_code,
    LEAST(source_intent.expires_at, now() + interval '6 hours')
  );
  RETURN true;
END; $$;

REVOKE ALL ON FUNCTION vido.preserve_searchy_card_source() FROM PUBLIC;
REVOKE ALL ON FUNCTION vido.create_shared_vido_intent(
  bytea,bytea,bigint,bigint,bigint,text,text,text,text
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION vido.create_shared_vido_intent(
  bytea,bytea,bigint,bigint,bigint,text,text,text,text
) TO searchy_core;

REVOKE ALL ON ALL TABLES IN SCHEMA vido FROM searchy_core;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA vido FROM searchy_core;
