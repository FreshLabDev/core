-- The three SECURITY DEFINER functions migration 011 missed are no longer
-- reachable by every role that can connect, and clear_language is reachable by
-- exactly the six bots that need it.

SELECT NOT has_function_privilege(
       'public', 'core.clear_language(text,core.pref_scope,bigint)', 'EXECUTE')
   AND NOT has_function_privilege(
       'public', 'core.rekey_chat(bigint,bigint)', 'EXECUTE')
   AND NOT has_function_privilege(
       'public', 'core.resolve_language(core.pref_scope,bigint)', 'EXECUTE')
  AS public_is_shut_out \gset
\if :public_is_shut_out
\else
  \quit 1
\endif

SELECT has_function_privilege(
       'vido_core', 'core.clear_language(text,core.pref_scope,bigint)', 'EXECUTE')
   AND has_function_privilege(
       'searchy_core', 'core.clear_language(text,core.pref_scope,bigint)', 'EXECUTE')
   AND has_function_privilege(
       'quoto_core', 'core.clear_language(text,core.pref_scope,bigint)', 'EXECUTE')
   AND has_function_privilege(
       'branchy_core', 'core.clear_language(text,core.pref_scope,bigint)', 'EXECUTE')
   AND has_function_privilege(
       'makeitmd_core', 'core.clear_language(text,core.pref_scope,bigint)', 'EXECUTE')
   AND has_function_privilege(
       'voicy_core', 'core.clear_language(text,core.pref_scope,bigint)', 'EXECUTE')
  AS every_bot_can_clear \gset
\if :every_bot_can_clear
\else
  \quit 1
\endif

-- Re-keying a chat is an operator action, not something a bot does, so no bot
-- role holds it even though the revoke above only named PUBLIC.
SELECT NOT has_function_privilege(
       'voicy_core', 'core.rekey_chat(bigint,bigint)', 'EXECUTE')
   AND NOT has_function_privilege(
       'quoto_core', 'core.rekey_chat(bigint,bigint)', 'EXECUTE')
  AS rekey_is_operator_only \gset
\if :rekey_is_operator_only
\else
  \quit 1
\endif

-- The point of the revoke is that it does not break the path it guards: a bot
-- clearing its own observation still works, and the internal PERFORM of
-- resolve_language still runs because clear_language is SECURITY DEFINER and
-- owned by core.
SELECT core.touch(
  'voicy', 12001, 'privilege_test', 'Privilege', NULL, 'de',
  NULL, NULL, NULL, NULL, false
);

SET ROLE voicy_core;
SELECT core.set_language('voicy', 'user', 12001, 'ru', 'manual');
SELECT core.clear_language('voicy', 'user', 12001);
RESET ROLE;

-- With the manual choice withdrawn, the Telegram hint recorded by touch wins
-- again. That is the whole behaviour the "follow Telegram" button promises.
SELECT core.effective_language(12001, NULL, 'user') = 'de' AS hint_wins_again \gset
\if :hint_wins_again
\else
  \quit 1
\endif
