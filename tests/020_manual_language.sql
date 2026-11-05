-- core.manual_language answers whether a language was picked by hand: maply
-- can ask, nobody else can, and a Telegram hint or a detected language is not
-- an answer.

-- Every grant is listed, so a later blanket GRANT EXECUTE ON ALL FUNCTIONS
-- to some role fails here too: only maply_core besides the owner, and not
-- PUBLIC (grantee 0).
SELECT NOT has_function_privilege(
       'public', 'core.manual_language(core.pref_scope,bigint)', 'EXECUTE')
   AND (SELECT array_agg(DISTINCT a.grantee::regrole::text)
          FROM pg_proc p, aclexplode(p.proacl) a
         WHERE p.oid = 'core.manual_language(core.pref_scope,bigint)'::regprocedure
           AND a.privilege_type = 'EXECUTE'
           AND a.grantee <> p.proowner) = ARRAY['maply_core']
  AS only_maply \gset
\if :only_maply
\else
  DO $$ BEGIN RAISE EXCEPTION 'contract failed: 020_manual_language.sql: expected only_maply to be true'; END $$;
\endif

-- Russian Telegram app, Ukrainian picked in another bot: the screen language
-- is the pick, and maply can see it was one.
SELECT core.touch(
  'maply', 20001, 'manual_test', 'Manual', NULL, 'ru',
  -1002000000001, 'supergroup', 'Group', NULL, false
);

SET ROLE maply_core;
SELECT core.manual_language('user', 20001) IS NULL AS hint_is_not_a_pick \gset
RESET ROLE;
\if :hint_is_not_a_pick
\else
  DO $$ BEGIN RAISE EXCEPTION 'contract failed: 020_manual_language.sql: expected hint_is_not_a_pick to be true'; END $$;
\endif

SET ROLE vido_core;
SELECT core.set_language('vido', 'user', 20001, 'uk', 'manual');
RESET ROLE;
SET ROLE quoto_core;
SELECT core.set_language('quoto', 'chat', -1002000000001, 'ru', 'auto');
RESET ROLE;

SET ROLE maply_core;
SELECT core.manual_language('user', 20001) = 'uk'
   AND core.effective_language(20001, NULL, 'user') = 'uk'
   AND core.manual_language('chat', -1002000000001) IS NULL
   AND core.effective_language(20001, -1002000000001, 'chat') = 'ru'
  AS pick_seen_across_bots \gset
\if :pick_seen_across_bots
\else
  DO $$ BEGIN RAISE EXCEPTION 'contract failed: 020_manual_language.sql: expected pick_seen_across_bots to be true'; END $$;
\endif

-- An admin's pick for the group is one too.
SELECT core.set_language('maply', 'chat', -1002000000001, 'uk', 'manual');
SELECT core.manual_language('chat', -1002000000001) = 'uk' AS chat_pick_seen \gset
\if :chat_pick_seen
\else
  DO $$ BEGIN RAISE EXCEPTION 'contract failed: 020_manual_language.sql: expected chat_pick_seen to be true'; END $$;
\endif
RESET ROLE;

-- Follow Telegram withdraws the pick, and the answer goes with it.
SET ROLE vido_core;
SELECT core.clear_language('vido', 'user', 20001);
RESET ROLE;
SET ROLE maply_core;
SELECT core.manual_language('user', 20001) IS NULL AS withdrawn \gset
RESET ROLE;
\if :withdrawn
\else
  DO $$ BEGIN RAISE EXCEPTION 'contract failed: 020_manual_language.sql: expected withdrawn to be true'; END $$;
\endif
