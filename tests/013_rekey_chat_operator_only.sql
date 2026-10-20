-- Re-keying a chat is an operator action: after 013 no bot role can execute
-- core.rekey_chat, and the core owner still can.

SELECT NOT has_function_privilege(
       'vido_core', 'core.rekey_chat(bigint,bigint)', 'EXECUTE')
   AND NOT has_function_privilege(
       'searchy_core', 'core.rekey_chat(bigint,bigint)', 'EXECUTE')
   AND NOT has_function_privilege(
       'quoto_core', 'core.rekey_chat(bigint,bigint)', 'EXECUTE')
   AND NOT has_function_privilege(
       'branchy_core', 'core.rekey_chat(bigint,bigint)', 'EXECUTE')
   AND NOT has_function_privilege(
       'makeitmd_core', 'core.rekey_chat(bigint,bigint)', 'EXECUTE')
   AND NOT has_function_privilege(
       'voicy_core', 'core.rekey_chat(bigint,bigint)', 'EXECUTE')
  AS no_bot_can_rekey \gset
\if :no_bot_can_rekey
\else
  DO $$ BEGIN RAISE EXCEPTION 'contract failed: 013_rekey_chat_operator_only.sql: expected no_bot_can_rekey to be true'; END $$;
\endif

SELECT has_function_privilege(
       'core', 'core.rekey_chat(bigint,bigint)', 'EXECUTE')
  AS owner_can_rekey \gset
\if :owner_can_rekey
\else
  DO $$ BEGIN RAISE EXCEPTION 'contract failed: 013_rekey_chat_operator_only.sql: expected owner_can_rekey to be true'; END $$;
\endif
