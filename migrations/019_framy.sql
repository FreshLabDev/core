-- core :: 019 - framy: register the bot and provision its schema and role
-- The central migrator owns the transaction.
--
-- framy owns framy.* and writes shared identity only through the SECURITY
-- DEFINER core API. It gets less than maply: no SELECT on any core table. It
-- learns who a person is from the update or from the Telegram Login claims,
-- and its tables point at core.person and core.chat by foreign key, which
-- needs REFERENCES only: PostgreSQL runs the key check as the owner of the
-- referenced table.

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

DO $$ BEGIN CREATE ROLE framy_core LOGIN; EXCEPTION WHEN duplicate_object THEN NULL; END $$;

INSERT INTO core.bot(bot) VALUES ('framy')
ON CONFLICT (bot) DO NOTHING;

-- The service runs its own migrations, so it owns its schema.
CREATE SCHEMA IF NOT EXISTS framy AUTHORIZATION framy_core;
ALTER SCHEMA framy OWNER TO framy_core;
REVOKE ALL ON SCHEMA framy FROM PUBLIC;

GRANT USAGE ON SCHEMA core TO framy_core;
GRANT REFERENCES ON core.person, core.chat TO framy_core;

-- PUBLIC lost these in 011 and 012, so each bot needs its own grant.
GRANT EXECUTE ON FUNCTION core.touch(
  text,bigint,text,text,text,text,bigint,text,text,text,boolean,timestamptz
) TO framy_core;
GRANT EXECUTE ON FUNCTION core.set_language(
  text,core.pref_scope,bigint,text,core.lang_source
) TO framy_core;
GRANT EXECUTE ON FUNCTION core.clear_language(
  text,core.pref_scope,bigint
) TO framy_core;
GRANT EXECUTE ON FUNCTION core.effective_language(
  bigint,bigint,core.pref_scope
) TO framy_core;

-- framy speaks mostly to one person, in a DM, on the site and in the Mini App:
-- a peer language consumer, the tier of vido and voicy.
CREATE OR REPLACE FUNCTION core.bot_rank(b text) RETURNS int
LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE b WHEN 'quoto' THEN 4 WHEN 'searchy' THEN 3
                WHEN 'vido' THEN 2 WHEN 'voicy' THEN 2 WHEN 'framy' THEN 2
                WHEN 'branchy' THEN 1 WHEN 'maply' THEN 1 ELSE 0 END;
$$;

DO $$
BEGIN
  EXECUTE format(
    'ALTER ROLE framy_core IN DATABASE %I SET search_path = framy',
    current_database()
  );
END $$;
