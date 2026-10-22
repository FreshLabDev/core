-- maply has its bot row, owns its schema, and reaches core only through the
-- functions, the identity tables it reads, and its own slice of presence.

SELECT EXISTS (SELECT 1 FROM core.bot WHERE bot = 'maply')
   AND EXISTS (
     SELECT 1 FROM pg_namespace n JOIN pg_roles r ON r.oid = n.nspowner
      WHERE n.nspname = 'maply' AND r.rolname = 'maply_core')
  AS registered \gset
\if :registered
\else
  DO $$ BEGIN RAISE EXCEPTION 'contract failed: 018_maply.sql: expected registered to be true'; END $$;
\endif

SELECT has_table_privilege('maply_core', 'core.person', 'SELECT')
   AND has_table_privilege('maply_core', 'core.chat', 'SELECT')
   AND has_table_privilege('maply_core', 'core.person', 'REFERENCES')
   AND has_table_privilege('maply_core', 'core.maply_presence', 'SELECT')
   AND NOT has_table_privilege('maply_core', 'core.presence', 'SELECT')
   AND NOT has_table_privilege('maply_core', 'core.bot', 'SELECT')
   AND NOT has_table_privilege('maply_core', 'core.language_pref', 'SELECT')
   AND NOT has_table_privilege('public', 'core.maply_presence', 'SELECT')
   AND NOT has_table_privilege('voicy_core', 'core.maply_presence', 'SELECT')
   AND NOT has_table_privilege('maply_core', 'core.person', 'INSERT')
   AND NOT has_table_privilege('maply_core', 'core.person', 'UPDATE')
   AND NOT has_table_privilege('maply_core', 'core.person', 'DELETE')
   AND NOT has_table_privilege('maply_core', 'core.chat', 'INSERT')
   AND NOT has_table_privilege('maply_core', 'core.chat', 'UPDATE')
   AND NOT has_table_privilege('maply_core', 'core.presence', 'INSERT')
   AND has_function_privilege(
     'maply_core',
     'core.touch(text,bigint,text,text,text,text,bigint,text,text,text,boolean,timestamptz)',
     'EXECUTE')
   AND has_function_privilege(
     'maply_core', 'core.set_language(text,core.pref_scope,bigint,text,core.lang_source)', 'EXECUTE')
   AND has_function_privilege(
     'maply_core', 'core.clear_language(text,core.pref_scope,bigint)', 'EXECUTE')
   AND has_function_privilege(
     'maply_core', 'core.effective_language(bigint,bigint,core.pref_scope)', 'EXECUTE')
   AND NOT has_function_privilege('maply_core', 'core.rekey_chat(bigint,bigint)', 'EXECUTE')
  AS least_privilege \gset
\if :least_privilege
\else
  DO $$ BEGIN RAISE EXCEPTION 'contract failed: 018_maply.sql: expected least_privilege to be true'; END $$;
\endif

-- Another bot sees the same person in another group. maply must not learn that.
SELECT core.touch(
  'voicy', 18001, 'maply_test', 'Maply', NULL, 'uk',
  -1001800000002, 'supergroup', 'Elsewhere', NULL, false
);

SET ROLE maply_core;

SELECT core.touch(
  'maply', 18001, 'maply_test', 'Maply', NULL, 'uk',
  -1001800000001, 'supergroup', 'Maps', NULL, false
);
SELECT core.touch(
  'maply', 18001, 'maply_test', 'Maply', NULL, 'uk',
  NULL, NULL, NULL, NULL, false
);

SELECT array_agg(chat_id ORDER BY chat_id) = ARRAY[-1001800000001, 0]::bigint[]
  AS sees_only_its_presence
  FROM core.maply_presence
 WHERE telegram_user_id = 18001 \gset
\if :sees_only_its_presence
\else
  DO $$ BEGIN RAISE EXCEPTION 'contract failed: 018_maply.sql: expected sees_only_its_presence to be true'; END $$;
\endif

SELECT (SELECT first_name FROM core.person WHERE telegram_user_id = 18001) = 'Maply'
   AND (SELECT title FROM core.chat WHERE chat_id = -1001800000001) = 'Maps'
  AS reads_identity \gset
\if :reads_identity
\else
  DO $$ BEGIN RAISE EXCEPTION 'contract failed: 018_maply.sql: expected reads_identity to be true'; END $$;
\endif

SELECT core.set_language('maply', 'chat', -1001800000001, 'be', 'manual');
SELECT core.effective_language(18001, -1001800000001, 'chat') = 'be'
  AS language_round_trip \gset
\if :language_round_trip
\else
  DO $$ BEGIN RAISE EXCEPTION 'contract failed: 018_maply.sql: expected language_round_trip to be true'; END $$;
\endif

-- The service creates its own tables.
CREATE TABLE maply.contract_probe (id int);
DROP TABLE maply.contract_probe;

-- Direct writes to core are refused, whatever the table.
DO $$
BEGIN
  BEGIN
    UPDATE core.person SET first_name = 'Forged' WHERE telegram_user_id = 18001;
    RAISE EXCEPTION 'contract failed: 018_maply.sql: maply_core updated core.person directly';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    INSERT INTO core.chat(chat_id) VALUES (-1001800000003);
    RAISE EXCEPTION 'contract failed: 018_maply.sql: maply_core inserted into core.chat directly';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    INSERT INTO core.presence(telegram_user_id, bot, chat_id) VALUES (18001, 'maply', -1001800000003);
    RAISE EXCEPTION 'contract failed: 018_maply.sql: maply_core inserted into core.presence directly';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    PERFORM 1 FROM core.presence;
    RAISE EXCEPTION 'contract failed: 018_maply.sql: maply_core read core.presence directly';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END $$;

RESET ROLE;

SELECT s.setconfig @> ARRAY['search_path=maply'] AS search_path_is_maply
  FROM pg_db_role_setting s
  JOIN pg_roles r ON r.oid = s.setrole
 WHERE r.rolname = 'maply_core'
   AND s.setdatabase = (SELECT oid FROM pg_database WHERE datname = current_database()) \gset
\if :search_path_is_maply
\else
  DO $$ BEGIN RAISE EXCEPTION 'contract failed: 018_maply.sql: expected search_path_is_maply to be true'; END $$;
\endif
