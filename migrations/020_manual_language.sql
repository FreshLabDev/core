-- core :: 020 - core.manual_language: the language a person picked by hand
-- The central migrator owns the transaction.
--
-- effective_language says which language wins, not why. maply speaks a
-- group's language in the group, but a person who picked a language in any
-- bot of the family should read their own screen in it; the language of
-- their Telegram app is not such a choice. This answers only that question:
-- the winning language of a user or chat when it was picked by hand, NULL
-- otherwise. It reads core.language_pref as core, so the caller needs no
-- privilege on the table and learns nothing about the other sources.

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

CREATE OR REPLACE FUNCTION core.manual_language(
  p_scope core.pref_scope, p_subject bigint
) RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, core AS $$
  SELECT language FROM core.language_pref
   WHERE scope = p_scope AND subject_id = p_subject AND source = 'manual';
$$;

-- Revoked in the migration that creates it, granted to the one bot that asks.
REVOKE EXECUTE ON FUNCTION core.manual_language(core.pref_scope,bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION core.manual_language(core.pref_scope,bigint) TO maply_core;
