-- ============================================================================
-- core :: 002 — least-privilege login roles + grants (one role per bot)
-- Roles are created with LOGIN but NO usable password here; bin/apply.sh sets
-- each password from env (VIDO_CORE_PASSWORD, ...) after migrations run.
-- Bots get SELECT + EXECUTE only — NO raw INSERT/UPDATE on core.* tables.
-- Writes happen exclusively through the SECURITY DEFINER API functions.
-- Idempotent: safe to re-run.
-- ============================================================================

DO $$ BEGIN CREATE ROLE vido_core    LOGIN; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE ROLE searchy_core LOGIN; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE ROLE quoto_core   LOGIN; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE ROLE branchy_core LOGIN; EXCEPTION WHEN duplicate_object THEN NULL; END $$;

GRANT USAGE ON SCHEMA core TO vido_core, searchy_core, quoto_core, branchy_core;

-- read: tables + views (effective_language / who_was_where read language_pref etc.)
GRANT SELECT ON ALL TABLES IN SCHEMA core
  TO vido_core, searchy_core, quoto_core, branchy_core;

-- execute: the API + the pure helpers referenced by SECURITY INVOKER functions
-- (effective_language references core.lang_rank as the invoking bot role).
-- All core functions are safe to execute: helpers are pure; table writes require
-- table privileges the bot roles do NOT hold, so only the SECURITY DEFINER path writes.
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA core
  TO vido_core, searchy_core, quoto_core, branchy_core;

-- Future tables/functions added by later migrations must re-run the grants above,
-- or set ALTER DEFAULT PRIVILEGES for the migration owner. Kept explicit for now.
