-- core :: 003 — register makeitMD and provision its isolated schema/role
-- The bot owns only makeitmd.* and reaches shared identity through the
-- SECURITY DEFINER core API, matching the existing bot-family boundary.

DO $$ BEGIN CREATE ROLE makeitmd_core LOGIN; EXCEPTION WHEN duplicate_object THEN NULL; END $$;

INSERT INTO core.bot(bot) VALUES ('makeitmd')
ON CONFLICT (bot) DO NOTHING;

CREATE SCHEMA IF NOT EXISTS makeitmd AUTHORIZATION makeitmd_core;
ALTER SCHEMA makeitmd OWNER TO makeitmd_core;

GRANT USAGE ON SCHEMA core TO makeitmd_core;
GRANT SELECT ON ALL TABLES IN SCHEMA core TO makeitmd_core;
GRANT REFERENCES ON core.person, core.chat TO makeitmd_core;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA core TO makeitmd_core;
