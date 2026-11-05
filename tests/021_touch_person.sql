-- core.touch_person records a person and nothing about where they were seen:
-- no chat, no presence, so no DM context. Only maply may call it.

-- Every grant is listed, so a later blanket GRANT EXECUTE ON ALL FUNCTIONS
-- to some role fails here too: only maply_core besides the owner, and not
-- PUBLIC (grantee 0).
SELECT NOT has_function_privilege(
       'public', 'core.touch_person(text,bigint,text,text,text,text,boolean,timestamptz)', 'EXECUTE')
   AND (SELECT array_agg(DISTINCT a.grantee::regrole::text)
          FROM pg_proc p, aclexplode(p.proacl) a
         WHERE p.oid = 'core.touch_person(text,bigint,text,text,text,text,boolean,timestamptz)'::regprocedure
           AND a.privilege_type = 'EXECUTE'
           AND a.grantee <> p.proowner) = ARRAY['maply_core']
  AS only_maply \gset
\if :only_maply
\else
  DO $$ BEGIN RAISE EXCEPTION 'contract failed: 021_touch_person.sql: expected only_maply to be true'; END $$;
\endif

-- A person who signs in on the website: the person, the name and the language
-- hint are kept, and maply's slice of presence stays empty.
SET ROLE maply_core;
SELECT core.touch_person('maply', 21001, 'site_only', 'Site', NULL, 'uk');
SELECT EXISTS (SELECT 1 FROM core.person
                WHERE telegram_user_id = 21001 AND username = 'site_only' AND first_name = 'Site')
   AND NOT EXISTS (SELECT 1 FROM core.maply_presence WHERE telegram_user_id = 21001)
   AND core.effective_language(21001, NULL, 'user') = 'uk'
  AS person_without_presence \gset
RESET ROLE;
\if :person_without_presence
\else
  DO $$ BEGIN RAISE EXCEPTION 'contract failed: 021_touch_person.sql: expected person_without_presence to be true'; END $$;
\endif

SELECT NOT EXISTS (SELECT 1 FROM core.presence WHERE telegram_user_id = 21001)
   AND (SELECT count(*) FROM core.person_name_history WHERE telegram_user_id = 21001) = 1
  AS no_presence_one_name \gset
\if :no_presence_one_name
\else
  DO $$ BEGIN RAISE EXCEPTION 'contract failed: 021_touch_person.sql: expected no_presence_one_name to be true'; END $$;
\endif

-- A person who already plays in a group: touch_person leaves that presence as
-- it was and adds no DM, and an unchanged name writes no second history row.
SELECT core.touch(
  'maply', 21002, 'group_player', 'Group', NULL, 'ru',
  -1002100000001, 'supergroup', 'Group', NULL, false
);
SET ROLE maply_core;
SELECT core.touch_person('maply', 21002, 'group_player', 'Group', NULL, 'ru');
RESET ROLE;
SELECT (SELECT array_agg(chat_id ORDER BY chat_id) FROM core.presence
         WHERE telegram_user_id = 21002 AND bot = 'maply') = ARRAY[-1002100000001::bigint]
   AND (SELECT event_count FROM core.presence
         WHERE telegram_user_id = 21002 AND bot = 'maply' AND chat_id = -1002100000001) = 1
   AND (SELECT count(*) FROM core.person_name_history WHERE telegram_user_id = 21002) = 1
  AS group_presence_untouched \gset
\if :group_presence_untouched
\else
  DO $$ BEGIN RAISE EXCEPTION 'contract failed: 021_touch_person.sql: expected group_presence_untouched to be true'; END $$;
\endif

-- A new username is history, as it is for touch.
SET ROLE maply_core;
SELECT core.touch_person('maply', 21002, 'renamed', 'Group', NULL, NULL);
RESET ROLE;
SELECT (SELECT username FROM core.person WHERE telegram_user_id = 21002) = 'renamed'
   AND (SELECT count(*) FROM core.person_name_history WHERE telegram_user_id = 21002) = 2
  AS rename_kept \gset
\if :rename_kept
\else
  DO $$ BEGIN RAISE EXCEPTION 'contract failed: 021_touch_person.sql: expected rename_kept to be true'; END $$;
\endif

-- Another bot cannot call it.
SELECT NOT has_function_privilege(
       'vido_core', 'core.touch_person(text,bigint,text,text,text,text,boolean,timestamptz)', 'EXECUTE')
  AS others_refused \gset
\if :others_refused
\else
  DO $$ BEGIN RAISE EXCEPTION 'contract failed: 021_touch_person.sql: expected others_refused to be true'; END $$;
\endif
