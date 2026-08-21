-- Voicy has one canonical identity and only the shared-core privileges it uses.

SELECT EXISTS (SELECT 1 FROM core.bot WHERE bot = 'voicy')
   AND NOT EXISTS (SELECT 1 FROM core.bot WHERE bot = 'voicetotext')
   AND EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'voicy')
   AND NOT EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'voicetotext')
   AND EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'voicy_core')
   AND NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'voicetotext_core')
  AS canonical_names \gset
\if :canonical_names
\else
  \quit 1
\endif

SELECT NOT has_table_privilege('voicy_core', 'core.bot', 'SELECT')
   AND has_table_privilege('voicy_core', 'core.person', 'REFERENCES')
   AND has_function_privilege(
     'voicy_core',
     'core.touch(text,bigint,text,text,text,text,bigint,text,text,text,boolean,timestamptz)',
     'EXECUTE'
   )
   AND has_function_privilege(
     'voicy_core',
     'core.set_language(text,core.pref_scope,bigint,text,core.lang_source)',
     'EXECUTE'
   )
   AND has_function_privilege(
     'voicy_core',
     'core.effective_language(bigint,bigint,core.pref_scope)',
     'EXECUTE'
   ) AS least_privilege \gset
\if :least_privilege
\else
  \quit 1
\endif

SET ROLE voicy_core;
SELECT core.touch(
  'voicy', 11001, 'voicy_test', 'Voicy', NULL, 'en',
  NULL, NULL, NULL, NULL, false
);
SELECT core.set_language('voicy', 'user', 11001, 'ru', 'manual');
SELECT core.effective_language(11001, NULL, 'user') = 'ru'
  AS language_round_trip \gset
\if :language_round_trip
\else
  \quit 1
\endif
RESET ROLE;

SELECT s.setconfig @> ARRAY['search_path=voicy'] AS search_path_is_voicy
  FROM pg_db_role_setting s
  JOIN pg_roles r ON r.oid = s.setrole
 WHERE r.rolname = 'voicy_core'
   AND s.setdatabase = (SELECT oid FROM pg_database WHERE datname = current_database()) \gset
\if :search_path_is_voicy
\else
  \quit 1
\endif
