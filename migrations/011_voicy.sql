-- core :: 011 - finish the Voicy rename and narrow its shared-core access
-- The central migrator owns the transaction. This migration preserves every
-- record written under the legacy bot key before removing that registry row.

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

INSERT INTO core.bot(bot) VALUES ('voicy')
ON CONFLICT (bot) DO NOTHING;

UPDATE core.person_name_history
   SET seen_by_bot = 'voicy'
 WHERE seen_by_bot = 'voicetotext';

INSERT INTO core.presence AS dst(
  telegram_user_id, bot, chat_id, first_seen_at, last_seen_at, event_count
)
SELECT telegram_user_id, 'voicy', chat_id, first_seen_at, last_seen_at, event_count
  FROM core.presence
 WHERE bot = 'voicetotext'
ON CONFLICT (telegram_user_id, bot, chat_id) DO UPDATE SET
  first_seen_at = LEAST(dst.first_seen_at, EXCLUDED.first_seen_at),
  last_seen_at = GREATEST(dst.last_seen_at, EXCLUDED.last_seen_at),
  event_count = dst.event_count + EXCLUDED.event_count;
DELETE FROM core.presence WHERE bot = 'voicetotext';

INSERT INTO core.language_observation AS dst(
  source_bot, scope, subject_id, language, source, observed_at
)
SELECT 'voicy', scope, subject_id, language, source, observed_at
  FROM core.language_observation
 WHERE source_bot = 'voicetotext'
ON CONFLICT (source_bot, scope, subject_id) DO UPDATE SET
  language = CASE
    WHEN core.lang_rank(EXCLUDED.source) > core.lang_rank(dst.source)
      OR (core.lang_rank(EXCLUDED.source) = core.lang_rank(dst.source)
          AND EXCLUDED.observed_at > dst.observed_at)
    THEN EXCLUDED.language ELSE dst.language END,
  source = CASE
    WHEN core.lang_rank(EXCLUDED.source) > core.lang_rank(dst.source)
      OR (core.lang_rank(EXCLUDED.source) = core.lang_rank(dst.source)
          AND EXCLUDED.observed_at > dst.observed_at)
    THEN EXCLUDED.source ELSE dst.source END,
  observed_at = GREATEST(dst.observed_at, EXCLUDED.observed_at);
DELETE FROM core.language_observation WHERE source_bot = 'voicetotext';

UPDATE core.language_pref
   SET decided_from = 'voicy'
 WHERE decided_from = 'voicetotext';
UPDATE core.pref
   SET updated_by_bot = 'voicy'
 WHERE updated_by_bot = 'voicetotext';

SELECT core.resolve_language(scope, subject_id)
  FROM core.language_observation
 WHERE source_bot = 'voicy';

DELETE FROM core.bot WHERE bot = 'voicetotext';

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'voicetotext')
     AND NOT EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'voicy') THEN
    ALTER SCHEMA voicetotext RENAME TO voicy;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'voicetotext_core')
     AND NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'voicy_core') THEN
    ALTER ROLE voicetotext_core RENAME TO voicy_core;
  END IF;
END $$;

ALTER SCHEMA voicy OWNER TO voicy_core;
REVOKE ALL ON ALL TABLES IN SCHEMA core FROM voicy_core;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA core FROM voicy_core;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA core FROM voicy_core;
GRANT USAGE ON SCHEMA core TO voicy_core;
GRANT REFERENCES ON core.person, core.chat TO voicy_core;

CREATE OR REPLACE FUNCTION core.effective_language(
  p_user bigint, p_chat bigint DEFAULT NULL, p_prefer core.pref_scope DEFAULT 'user'
) RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, core AS $$
  SELECT language FROM core.language_pref
   WHERE (scope = 'user' AND subject_id = p_user)
      OR (scope = 'chat' AND subject_id = p_chat AND p_chat IS NOT NULL)
   ORDER BY (scope = p_prefer) DESC, core.lang_rank(source) DESC, updated_at DESC
   LIMIT 1;
$$;

-- Bot roles already have explicit grants from migrations 002, 003, and 009.
-- Removing PUBLIC access makes an explicit per-role grant meaningful.
REVOKE EXECUTE ON FUNCTION core.touch(
  text,bigint,text,text,text,text,bigint,text,text,text,boolean,timestamptz
) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION core.set_language(
  text,core.pref_scope,bigint,text,core.lang_source
) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION core.effective_language(
  bigint,bigint,core.pref_scope
) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION core.touch(
  text,bigint,text,text,text,text,bigint,text,text,text,boolean,timestamptz
) TO voicy_core;
GRANT EXECUTE ON FUNCTION core.set_language(
  text,core.pref_scope,bigint,text,core.lang_source
) TO voicy_core;
GRANT EXECUTE ON FUNCTION core.effective_language(
  bigint,bigint,core.pref_scope
) TO voicy_core;

CREATE OR REPLACE FUNCTION core.bot_rank(b text) RETURNS int
LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE b WHEN 'quoto' THEN 4 WHEN 'searchy' THEN 3
                WHEN 'vido' THEN 2 WHEN 'voicy' THEN 2
                WHEN 'branchy' THEN 1 ELSE 0 END;
$$;

DO $$
BEGIN
  EXECUTE format(
    'ALTER ROLE voicy_core IN DATABASE %I SET search_path = voicy',
    current_database()
  );
END $$;
