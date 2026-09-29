-- core :: 013 - take rekey_chat away from the bot roles
-- The central migrator owns the transaction.
--
-- Migration 012 meant to leave core.rekey_chat to the core owner alone, but it
-- only revoked PUBLIC. vido, searchy, quoto, branchy and makeitmd hold their own
-- explicit EXECUTE on it, granted by GRANT EXECUTE ON ALL FUNCTIONS in 002 and
-- 003, so every one of them could still re-point any chat id across core through
-- a SECURITY DEFINER function. voicy does not: 011 revoked everything from it.
--
-- No bot calls rekey_chat. Telegram's supergroup migration is handled by each
-- bot inside its own schema, so nothing loses a path it uses.

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

REVOKE EXECUTE ON FUNCTION core.rekey_chat(bigint,bigint)
  FROM vido_core, searchy_core, quoto_core, branchy_core, makeitmd_core;
