-- core :: 009 — register voicetotext and provision its isolated schema/role
-- The bot owns only voicetotext.* and reaches shared identity through the
-- SECURITY DEFINER core API, matching 003_makeitmd.sql.

DO $$ BEGIN CREATE ROLE voicetotext_core LOGIN; EXCEPTION WHEN duplicate_object THEN NULL; END $$;

INSERT INTO core.bot(bot) VALUES ('voicetotext')
ON CONFLICT (bot) DO NOTHING;

CREATE SCHEMA IF NOT EXISTS voicetotext AUTHORIZATION voicetotext_core;
ALTER SCHEMA voicetotext OWNER TO voicetotext_core;

GRANT USAGE ON SCHEMA core TO voicetotext_core;
GRANT SELECT ON ALL TABLES IN SCHEMA core TO voicetotext_core;
GRANT REFERENCES ON core.person, core.chat TO voicetotext_core;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA core TO voicetotext_core;
