\set ON_ERROR_STOP on

SET ROLE searchy_core;
SELECT vido.create_download_intent(
  decode(repeat('12', 32), 'hex'),
  50, 'video', 'searchy_chat', 'https://example.com/watch/shared',
  'other', 'searchy_chat', now() + interval '6 hours', -10050,
  'owner', 'Card', 'Owner', 'en', NULL
);
SELECT vido.bind_intent_message(
  decode(repeat('12', 32), 'hex'), 50, -10050, 500
) AS bound \gset
\if :bound
\else
  \quit 1
\endif

DO $$
BEGIN
  PERFORM vido.create_shared_vido_intent(
    decode(repeat('12', 32), 'hex'), decode(repeat('13', 32), 'hex'),
    51, -10050, 501, 'guest', 'Guest', NULL, 'en'
  );
  RAISE EXCEPTION 'wrong message context was accepted';
EXCEPTION WHEN insufficient_privilege THEN
  NULL;
END $$;

SELECT vido.create_shared_vido_intent(
  decode(repeat('12', 32), 'hex'), decode(repeat('13', 32), 'hex'),
  51, -10050, 500, 'guest', 'Guest', NULL, 'en'
) AS shared \gset
\if :shared
\else
  \quit 1
\endif

-- The owner can still start delivery in the original chat.
SELECT job_id FROM vido.enqueue_searchy_job(
  decode(repeat('12', 32), 'hex'), 50, -10050, NULL, 500,
  'callback:owner'
) \gset owner_

-- The source remains derivable after the owner has consumed the card intent.
SELECT vido.create_shared_vido_intent(
  decode(repeat('12', 32), 'hex'), decode(repeat('14', 32), 'hex'),
  52, -10050, 500, 'second', 'Second', NULL, 'en'
) AS shared_after_owner \gset
\if :shared_after_owner
\else
  \quit 1
\endif

DO $$
BEGIN
  PERFORM count(*) FROM vido.download_intents;
  RAISE EXCEPTION 'searchy_core read a private table';
EXCEPTION WHEN insufficient_privilege THEN
  NULL;
END $$;
RESET ROLE;

SELECT EXISTS (
  SELECT 1 FROM vido.download_intents
   WHERE token_hash = decode(repeat('12', 32), 'hex')
     AND consumed_at IS NOT NULL
     AND job_id = :owner_job_id
     AND source_url = 'https://example.com/watch/shared'
) AS source_preserved \gset
\if :source_preserved
\else
  \quit 1
\endif

-- Private Searchy cards are not shareable and keep the previous immediate
-- consume-and-clear behavior.
SET ROLE searchy_core;
SELECT vido.create_download_intent(
  decode(repeat('15', 32), 'hex'),
  53, 'video', 'searchy_chat', 'https://example.com/watch/private',
  'other', 'searchy_chat', now() + interval '6 hours', 53,
  'private', 'Private', NULL, 'en', NULL
);
SELECT vido.bind_intent_message(
  decode(repeat('15', 32), 'hex'), 53, 53, 530
) AS private_bound \gset
SELECT job_id FROM vido.enqueue_searchy_job(
  decode(repeat('15', 32), 'hex'), 53, 53, NULL, 530,
  'callback:private'
) \gset private_
RESET ROLE;

SELECT EXISTS (
  SELECT 1 FROM vido.download_intents
   WHERE token_hash = decode(repeat('15', 32), 'hex')
     AND job_id = :private_job_id
     AND source_url IS NULL
) AS private_source_cleared \gset
\if :private_source_cleared
\else
  \quit 1
\endif

SELECT (
  SELECT count(*) = 2
    FROM vido.download_intents
   WHERE token_hash IN (
     decode(repeat('13', 32), 'hex'), decode(repeat('14', 32), 'hex')
   )
     AND owner_user_id IN (51, 52)
     AND kind = 'video'
     AND delivery_mode = 'vido_dm'
     AND source_surface = 'searchy_shared'
     AND origin_chat_id = -10050
     AND origin_message_id = 500
     AND source_url = 'https://example.com/watch/shared'
     AND expires_at <= (
       SELECT expires_at FROM vido.download_intents
        WHERE token_hash = decode(repeat('12', 32), 'hex')
     )
) AS clones_are_bound \gset
\if :clones_are_bound
\else
  \quit 1
\endif

SELECT NOT has_function_privilege(
  'public',
  'vido.create_shared_vido_intent(bytea,bytea,bigint,bigint,bigint,text,text,text,text)',
  'EXECUTE'
) AS public_blocked \gset
\if :public_blocked
\else
  \quit 1
\endif
