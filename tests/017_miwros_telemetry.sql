-- After 017 the miwros site can write visits and nothing else, and no other
-- bot can touch them.

SELECT has_table_privilege('miwros_core', 'miwros.session', 'INSERT')
   AND has_table_privilege('miwros_core', 'miwros.session', 'UPDATE')
   AND has_table_privilege('miwros_core', 'miwros.event', 'INSERT')
   AND NOT has_table_privilege('miwros_core', 'miwros.event', 'UPDATE')
   AND NOT has_table_privilege('miwros_core', 'miwros.event', 'DELETE')
   AND NOT has_table_privilege('miwros_core', 'miwros.session', 'DELETE')
  AS writer_privileges \gset
\if :writer_privileges
\else
  DO $$ BEGIN RAISE EXCEPTION 'contract failed: 017_miwros_telemetry.sql: expected writer_privileges to be true'; END $$;
\endif

SELECT NOT has_schema_privilege('vido_core', 'miwros', 'USAGE')
   AND NOT has_schema_privilege('voicy_core', 'miwros', 'USAGE')
   AND NOT has_table_privilege('vido_core', 'miwros.session', 'SELECT')
   AND NOT has_schema_privilege('miwros_core', 'vido', 'USAGE')
   AND NOT has_table_privilege('miwros_core', 'core.person', 'SELECT')
  AS role_isolation \gset
\if :role_isolation
\else
  DO $$ BEGIN RAISE EXCEPTION 'contract failed: 017_miwros_telemetry.sql: expected role_isolation to be true'; END $$;
\endif

-- A session row takes events, and removing it takes them along.
INSERT INTO miwros.session (id, visitor_id)
VALUES ('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000aa');
INSERT INTO miwros.event (session_id, kind, name)
VALUES ('00000000-0000-4000-8000-000000000001', 'zone', 'desk');
DELETE FROM miwros.session WHERE id = '00000000-0000-4000-8000-000000000001';
SELECT count(*) = 0 AS events_follow_session FROM miwros.event
 WHERE session_id = '00000000-0000-4000-8000-000000000001'
\gset
\if :events_follow_session
\else
  DO $$ BEGIN RAISE EXCEPTION 'contract failed: 017_miwros_telemetry.sql: expected events_follow_session to be true'; END $$;
\endif
