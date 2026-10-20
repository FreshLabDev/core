-- After 016 Vido can write which provider served a bridge job.

SELECT count(*) = 3 AS route_columns_exist
  FROM information_schema.columns
 WHERE table_schema = 'vido' AND table_name = 'bridge_jobs'
   AND column_name IN ('provider', 'fallback_from', 'fallback_reason')
   AND data_type = 'text' AND is_nullable = 'YES'
\gset
\if :route_columns_exist
\else
  DO $$ BEGIN RAISE EXCEPTION 'contract failed: 016_vido_bridge_job_provider.sql: expected route_columns_exist to be true'; END $$;
\endif

SELECT has_column_privilege('vido_core', 'vido.bridge_jobs', 'provider', 'UPDATE')
   AND has_column_privilege('vido_core', 'vido.bridge_jobs', 'fallback_from', 'UPDATE')
   AND has_column_privilege('vido_core', 'vido.bridge_jobs', 'fallback_reason', 'UPDATE')
   AND NOT has_column_privilege('searchy_core', 'vido.bridge_jobs', 'provider', 'SELECT')
  AS route_privileges \gset
\if :route_privileges
\else
  DO $$ BEGIN RAISE EXCEPTION 'contract failed: 016_vido_bridge_job_provider.sql: expected route_privileges to be true'; END $$;
\endif
