-- core :: 017 - miwros: visit telemetry for the personal site
-- Not a Telegram bot and not tied to core.person: visitors are anonymous
-- browsers, so the schema keeps no foreign keys into the identity hub.
-- miwros_core writes (insert/update only); ws04web_ro, where it exists, reads.

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

DO $$ BEGIN CREATE ROLE miwros_core LOGIN; EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- The schema and its tables stay with the migrating owner: an owner always
-- holds UPDATE and DELETE, and the site must not.
CREATE SCHEMA IF NOT EXISTS miwros;

-- One row per browser tab session. The browser makes up both ids; the server
-- adds the address, the country and the parsed user agent from the request.
CREATE TABLE IF NOT EXISTS miwros.session (
  id            uuid        PRIMARY KEY,
  visitor_id    uuid        NOT NULL,
  started_at    timestamptz NOT NULL DEFAULT now(),
  last_seen_at  timestamptz NOT NULL DEFAULT now(),
  ip            inet,
  country       text,
  user_agent    text,
  device        text        NOT NULL DEFAULT 'unknown'
                CHECK (device IN ('desktop', 'mobile', 'tablet', 'bot', 'unknown')),
  os            text,
  browser       text,
  is_bot        boolean     NOT NULL DEFAULT false,
  language      text,
  timezone      text,
  screen        text,
  viewport      text,
  referrer      text,
  entry_path    text,
  -- What the door decided: the room ('room'), the desktop-only screen
  -- ('blocked'), the flat fallback ('no-webgl'), or a month page ('page').
  outcome       text,
  quality       text,
  event_count   integer     NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS session_started_idx ON miwros.session (started_at DESC);
CREATE INDEX IF NOT EXISTS session_visitor_idx ON miwros.session (visitor_id, started_at DESC);
CREATE INDEX IF NOT EXISTS session_ip_idx ON miwros.session (ip, started_at DESC);

CREATE TABLE IF NOT EXISTS miwros.event (
  id          bigint      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  session_id  uuid        NOT NULL REFERENCES miwros.session (id) ON DELETE CASCADE,
  at          timestamptz NOT NULL DEFAULT now(),
  kind        text        NOT NULL CHECK (char_length(kind) <= 32),
  name        text        CHECK (char_length(name) <= 64),
  props       jsonb       NOT NULL DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS event_session_idx ON miwros.event (session_id, at);
CREATE INDEX IF NOT EXISTS event_at_idx ON miwros.event (at DESC);
CREATE INDEX IF NOT EXISTS event_kind_idx ON miwros.event (kind, name, at DESC);

-- The site never deletes, and never edits an event once written.
REVOKE ALL ON SCHEMA miwros FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA miwros FROM PUBLIC;
GRANT USAGE ON SCHEMA miwros TO miwros_core;
GRANT SELECT, INSERT, UPDATE ON miwros.session TO miwros_core;
GRANT SELECT, INSERT ON miwros.event TO miwros_core;

-- The status panel reads through a role that migrations do not create; grant
-- only where it exists so a clean install still applies.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'ws04web_ro') THEN
    GRANT USAGE ON SCHEMA miwros TO ws04web_ro;
    GRANT SELECT ON miwros.session, miwros.event TO ws04web_ro;
  END IF;
END $$;
