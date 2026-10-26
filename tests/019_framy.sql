-- framy has its bot row, owns its schema, and reaches core only through the
-- functions and the foreign keys its tables point with. It reads no core table
-- and no other bot's schema.

SELECT EXISTS (SELECT 1 FROM core.bot WHERE bot = 'framy')
   AND EXISTS (
     SELECT 1 FROM pg_namespace n JOIN pg_roles r ON r.oid = n.nspowner
      WHERE n.nspname = 'framy' AND r.rolname = 'framy_core')
   AND core.bot_rank('framy') = 2
  AS registered \gset
\if :registered
\else
  DO $$ BEGIN RAISE EXCEPTION 'contract failed: 019_framy.sql: expected registered to be true'; END $$;
\endif

SELECT has_table_privilege('framy_core', 'core.person', 'REFERENCES')
   AND has_table_privilege('framy_core', 'core.chat', 'REFERENCES')
   AND NOT has_table_privilege('framy_core', 'core.person', 'SELECT')
   AND NOT has_table_privilege('framy_core', 'core.chat', 'SELECT')
   AND NOT has_table_privilege('framy_core', 'core.presence', 'SELECT')
   AND NOT has_table_privilege('framy_core', 'core.bot', 'SELECT')
   AND NOT has_table_privilege('framy_core', 'core.language_pref', 'SELECT')
   AND NOT has_table_privilege('framy_core', 'core.language_observation', 'SELECT')
   AND NOT has_table_privilege('framy_core', 'core.person', 'INSERT')
   AND NOT has_table_privilege('framy_core', 'core.person', 'UPDATE')
   AND NOT has_table_privilege('framy_core', 'core.person', 'DELETE')
   AND NOT has_table_privilege('framy_core', 'core.chat', 'INSERT')
   AND NOT has_table_privilege('framy_core', 'core.chat', 'UPDATE')
   AND NOT has_table_privilege('framy_core', 'core.presence', 'INSERT')
   AND NOT has_table_privilege('framy_core', 'core.maply_presence', 'SELECT')
   AND has_function_privilege(
     'framy_core',
     'core.touch(text,bigint,text,text,text,text,bigint,text,text,text,boolean,timestamptz)',
     'EXECUTE')
   AND has_function_privilege(
     'framy_core', 'core.set_language(text,core.pref_scope,bigint,text,core.lang_source)', 'EXECUTE')
   AND has_function_privilege(
     'framy_core', 'core.clear_language(text,core.pref_scope,bigint)', 'EXECUTE')
   AND has_function_privilege(
     'framy_core', 'core.effective_language(bigint,bigint,core.pref_scope)', 'EXECUTE')
   AND NOT has_function_privilege('framy_core', 'core.rekey_chat(bigint,bigint)', 'EXECUTE')
  AS least_privilege \gset
\if :least_privilege
\else
  DO $$ BEGIN RAISE EXCEPTION 'contract failed: 019_framy.sql: expected least_privilege to be true'; END $$;
\endif

-- No other schema is open to framy, and framy's is open to nobody else.
SELECT NOT EXISTS (
         SELECT 1 FROM pg_namespace
          WHERE nspname NOT IN ('framy', 'core', 'public', 'information_schema')
            AND nspname NOT LIKE 'pg\_%'
            AND has_schema_privilege('framy_core', oid, 'USAGE'))
   AND NOT has_schema_privilege('framy_core', 'public', 'CREATE')
   AND NOT has_schema_privilege('public', 'framy', 'USAGE')
   AND NOT has_schema_privilege('maply_core', 'framy', 'USAGE')
   AND NOT has_schema_privilege('voicy_core', 'framy', 'USAGE')
  AS schemas_apart \gset
\if :schemas_apart
\else
  DO $$ BEGIN RAISE EXCEPTION 'contract failed: 019_framy.sql: expected schemas_apart to be true'; END $$;
\endif

SET ROLE framy_core;

-- A person in a DM, then in a group.
SELECT core.touch(
  'framy', 19001, 'framy_test', 'Framy', NULL, 'pl',
  NULL, NULL, NULL, NULL, false
);
SELECT core.touch(
  'framy', 19001, 'framy_test', 'Framy', NULL, 'pl',
  -1001900000001, 'supergroup', 'Frames', NULL, false
);

SELECT core.set_language('framy', 'user', 19001, 'pl', 'manual');
SELECT core.effective_language(19001, NULL, 'user') = 'pl'
  AS language_round_trip \gset
\if :language_round_trip
\else
  DO $$ BEGIN RAISE EXCEPTION 'contract failed: 019_framy.sql: expected language_round_trip to be true'; END $$;
\endif
SELECT core.clear_language('framy', 'user', 19001);
SELECT core.effective_language(19001, NULL, 'user') IS DISTINCT FROM 'pl'
  AS language_cleared \gset
\if :language_cleared
\else
  DO $$ BEGIN RAISE EXCEPTION 'contract failed: 019_framy.sql: expected language_cleared to be true'; END $$;
\endif

-- framy's own tables point at core by key without reading it.
CREATE TABLE framy.contract_probe (
  user_id bigint NOT NULL REFERENCES core.person(telegram_user_id),
  chat_id bigint REFERENCES core.chat(chat_id)
);
INSERT INTO framy.contract_probe VALUES (19001, -1001900000001);
DO $$
BEGIN
  BEGIN
    INSERT INTO framy.contract_probe VALUES (19099, NULL);
    RAISE EXCEPTION 'contract failed: 019_framy.sql: a row for an unknown person was accepted';
  EXCEPTION WHEN foreign_key_violation THEN NULL;
  END;
END $$;
DROP TABLE framy.contract_probe;

-- Direct reads and writes of core, and reads of another bot's schema, are refused.
DO $$
BEGIN
  BEGIN
    PERFORM 1 FROM core.person;
    RAISE EXCEPTION 'contract failed: 019_framy.sql: framy_core read core.person directly';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    PERFORM 1 FROM core.presence;
    RAISE EXCEPTION 'contract failed: 019_framy.sql: framy_core read core.presence directly';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    UPDATE core.person SET first_name = 'Forged' WHERE telegram_user_id = 19001;
    RAISE EXCEPTION 'contract failed: 019_framy.sql: framy_core updated core.person directly';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    INSERT INTO core.chat(chat_id) VALUES (-1001900000002);
    RAISE EXCEPTION 'contract failed: 019_framy.sql: framy_core inserted into core.chat directly';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    PERFORM 1 FROM maply.schema_migrations;
    RAISE EXCEPTION 'contract failed: 019_framy.sql: framy_core read the maply schema';
  EXCEPTION WHEN insufficient_privilege OR undefined_table THEN NULL;
  END;
END $$;

RESET ROLE;

-- core saw the person and the group through framy.
SELECT (SELECT first_name FROM core.person WHERE telegram_user_id = 19001) = 'Framy'
   AND (SELECT title FROM core.chat WHERE chat_id = -1001900000001) = 'Frames'
   AND (SELECT count(*) FROM core.presence WHERE telegram_user_id = 19001 AND bot = 'framy') = 2
  AS touched \gset
\if :touched
\else
  DO $$ BEGIN RAISE EXCEPTION 'contract failed: 019_framy.sql: expected touched to be true'; END $$;
\endif

SELECT s.setconfig @> ARRAY['search_path=framy'] AS search_path_is_framy
  FROM pg_db_role_setting s
  JOIN pg_roles r ON r.oid = s.setrole
 WHERE r.rolname = 'framy_core'
   AND s.setdatabase = (SELECT oid FROM pg_database WHERE datname = current_database()) \gset
\if :search_path_is_framy
\else
  DO $$ BEGIN RAISE EXCEPTION 'contract failed: 019_framy.sql: expected search_path_is_framy to be true'; END $$;
\endif
