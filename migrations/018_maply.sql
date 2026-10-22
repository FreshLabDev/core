-- core :: 018 - maply: register the bot and provision its schema and role
-- The central migrator owns the transaction.
--
-- maply owns maply.* and writes shared identity only through the SECURITY
-- DEFINER core API. Unlike 009, it gets no blanket SELECT on core: it reads
-- people and chats for the leaderboard, and its own presence through a view.

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

DO $$ BEGIN CREATE ROLE maply_core LOGIN; EXCEPTION WHEN duplicate_object THEN NULL; END $$;

INSERT INTO core.bot(bot) VALUES ('maply')
ON CONFLICT (bot) DO NOTHING;

-- The service runs its own migrations, so it owns its schema.
CREATE SCHEMA IF NOT EXISTS maply AUTHORIZATION maply_core;
ALTER SCHEMA maply OWNER TO maply_core;
REVOKE ALL ON SCHEMA maply FROM PUBLIC;

GRANT USAGE ON SCHEMA core TO maply_core;
GRANT SELECT, REFERENCES ON core.person, core.chat TO maply_core;

-- A person's answer window closes at the earliest reveal among every chat they
-- play in, so maply reads where core has seen them with maply. Only with maply:
-- which other bots a person uses is none of its business. The view runs with
-- its owner's rights and filters before a row reaches the caller, which is why
-- maply_core holds no privilege on core.presence itself.
CREATE OR REPLACE VIEW core.maply_presence WITH (security_barrier) AS
  SELECT telegram_user_id, chat_id, first_seen_at, last_seen_at
    FROM core.presence
   WHERE bot = 'maply';
REVOKE ALL ON core.maply_presence FROM PUBLIC;
GRANT SELECT ON core.maply_presence TO maply_core;

-- PUBLIC lost these in 011 and 012, so each bot needs its own grant.
GRANT EXECUTE ON FUNCTION core.touch(
  text,bigint,text,text,text,text,bigint,text,text,text,boolean,timestamptz
) TO maply_core;
GRANT EXECUTE ON FUNCTION core.set_language(
  text,core.pref_scope,bigint,text,core.lang_source
) TO maply_core;
GRANT EXECUTE ON FUNCTION core.clear_language(
  text,core.pref_scope,bigint
) TO maply_core;
GRANT EXECUTE ON FUNCTION core.effective_language(
  bigint,bigint,core.pref_scope
) TO maply_core;

-- maply asks for a language per chat, like branchy: the same tier.
CREATE OR REPLACE FUNCTION core.bot_rank(b text) RETURNS int
LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE b WHEN 'quoto' THEN 4 WHEN 'searchy' THEN 3
                WHEN 'vido' THEN 2 WHEN 'voicy' THEN 2
                WHEN 'branchy' THEN 1 WHEN 'maply' THEN 1 ELSE 0 END;
$$;

DO $$
BEGIN
  EXECUTE format(
    'ALTER ROLE maply_core IN DATABASE %I SET search_path = maply',
    current_database()
  );
END $$;
