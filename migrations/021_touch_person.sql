-- core :: 021 - core.touch_person: a person seen outside any chat
-- The central migrator owns the transaction.
--
-- core.touch always records presence: with no chat it counts the person as
-- talking to the bot in a DM (chat_id 0). maply reads presence to decide when
-- a person's daily answer closes and who gets its morning DM post, so a person
-- who signs in on maply's website with Telegram, or who joins a game with
-- friends from a link without ever opening the bot, must not get a DM they
-- never had. touch_person keeps the person, the name history and the Telegram
-- language hint exactly as touch does, and writes no chat and no presence.

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

CREATE OR REPLACE FUNCTION core.touch_person(
  p_bot text, p_user_id bigint,
  p_username text DEFAULT NULL, p_first_name text DEFAULT NULL, p_last_name text DEFAULT NULL,
  p_tg_lang text DEFAULT NULL, p_is_bot boolean DEFAULT false, p_at timestamptz DEFAULT now()
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, core AS $$
DECLARE v_old record; v_existed boolean;
BEGIN
  SELECT username, first_name, last_name INTO v_old
  FROM core.person WHERE telegram_user_id = p_user_id;
  v_existed := FOUND;

  INSERT INTO core.person AS pe (telegram_user_id, username, first_name, last_name, is_bot,
                                 tg_language_code, first_seen_at, last_seen_at)
  VALUES (p_user_id, p_username, p_first_name, p_last_name, p_is_bot, p_tg_lang, p_at, p_at)
  ON CONFLICT (telegram_user_id) DO UPDATE SET
    username         = COALESCE(EXCLUDED.username, pe.username),
    first_name       = COALESCE(EXCLUDED.first_name, pe.first_name),
    last_name        = COALESCE(EXCLUDED.last_name, pe.last_name),
    is_bot           = EXCLUDED.is_bot,
    tg_language_code = COALESCE(EXCLUDED.tg_language_code, pe.tg_language_code),
    first_seen_at    = LEAST(pe.first_seen_at, EXCLUDED.first_seen_at),
    last_seen_at     = GREATEST(pe.last_seen_at, EXCLUDED.last_seen_at),
    updated_at       = now();

  IF (NOT v_existed OR v_old.username IS DISTINCT FROM p_username
      OR v_old.first_name IS DISTINCT FROM p_first_name
      OR v_old.last_name IS DISTINCT FROM p_last_name)
     AND (p_username IS NOT NULL OR p_first_name IS NOT NULL OR p_last_name IS NOT NULL) THEN
    INSERT INTO core.person_name_history(telegram_user_id, username, first_name, last_name, seen_by_bot, observed_at)
    VALUES (p_user_id, p_username, p_first_name, p_last_name, p_bot, p_at);
  END IF;

  IF core.norm_lang(p_tg_lang) IS NOT NULL THEN
    INSERT INTO core.language_observation(source_bot, scope, subject_id, language, source, observed_at)
    VALUES (p_bot, 'user', p_user_id, core.norm_lang(p_tg_lang), 'client', p_at)
    ON CONFLICT (source_bot, scope, subject_id) DO NOTHING;
    PERFORM core.resolve_language('user', p_user_id);
  END IF;
END; $$;

-- Revoked in the migration that creates it, granted to the one bot that asks.
REVOKE EXECUTE ON FUNCTION core.touch_person(
  text,bigint,text,text,text,text,boolean,timestamptz
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION core.touch_person(
  text,bigint,text,text,text,text,boolean,timestamptz
) TO maply_core;
