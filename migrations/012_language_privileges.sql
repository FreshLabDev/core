-- core :: 012 - close the three SECURITY DEFINER functions migration 011 missed
-- The central migrator owns the transaction.
--
-- Migration 011 revoked PUBLIC from core.touch, core.set_language and
-- core.effective_language so that the per-role grants meant something. Three
-- functions of the same class were not in that list and are still executable by
-- every role that can connect:
--
--   core.clear_language  SECURITY DEFINER, deletes a bot's language observation
--   core.rekey_chat      SECURITY DEFINER, re-points a chat id across core
--   core.resolve_language          writes core.language_pref
--
-- Nothing about that was deliberate; they were simply not on the list. It
-- matters now because every bot is gaining a "follow Telegram" control that
-- calls clear_language, which makes it a routine path rather than a dormant
-- one, and a bot must not be able to clear another bot's observation.

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

-- clear_language is the counterpart of set_language: same shape, same callers,
-- so it gets the same treatment. vido, searchy, quoto, branchy and makeitmd
-- already hold an explicit grant; voicy never did and reached the function
-- through PUBLIC alone, so the revoke below would have broken it.
REVOKE EXECUTE ON FUNCTION core.clear_language(
  text,core.pref_scope,bigint
) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION core.clear_language(
  text,core.pref_scope,bigint
) TO vido_core, searchy_core, quoto_core, branchy_core, makeitmd_core, voicy_core;

-- rekey_chat has no caller outside core. Telegram's supergroup migration is
-- handled by each bot inside its own schema; quoto, the only bot that re-keys
-- anything, re-points its own tables and never calls this. So no bot role is
-- granted it: it stays available to the core owner for operator use.
REVOKE EXECUTE ON FUNCTION core.rekey_chat(bigint,bigint) FROM PUBLIC;

-- resolve_language is reached only through PERFORM inside touch, set_language,
-- clear_language and rekey_chat. Those are SECURITY DEFINER and owned by core,
-- so they keep executing it as core after this revoke. It is itself not
-- SECURITY DEFINER, so a bot calling it directly would already have failed on
-- core.language_pref; this only makes the boundary say so.
REVOKE EXECUTE ON FUNCTION core.resolve_language(
  core.pref_scope,bigint
) FROM PUBLIC;
