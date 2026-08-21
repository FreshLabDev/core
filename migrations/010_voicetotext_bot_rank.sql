-- core :: 010 — rank voicetotext in language tie-breaks
-- Without a rank its observations always lose the bot_rank tie-break in
-- core.resolve_language. Same tier as vido: a peer language consumer.

CREATE OR REPLACE FUNCTION core.bot_rank(b text) RETURNS int
LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE b WHEN 'quoto' THEN 4 WHEN 'searchy' THEN 3
                WHEN 'vido' THEN 2 WHEN 'voicetotext' THEN 2
                WHEN 'branchy' THEN 1 ELSE 0 END;
$$;
