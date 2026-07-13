\set ON_ERROR_STOP on

SET ROLE searchy_core;
SELECT vido.create_download_intent(
  decode(repeat('ab', 32), 'hex'),
  42, 'video', 'searchy_chat', 'https://example.com/watch/42',
  'other', 'searchy_chat', now() + interval '6 hours', -10042,
  'tester', 'Test', NULL, 'en', NULL
);
SELECT vido.bind_intent_message(
  decode(repeat('ab', 32), 'hex'), 42, -10042, 7
) AS bound \gset
\if :bound
\else
  \quit 1
\endif

DO $$
BEGIN
  PERFORM * FROM vido.enqueue_searchy_job(
    decode(repeat('ab', 32), 'hex'), 99, -10042, NULL, 7, 'wrong-owner'
  );
  RAISE EXCEPTION 'wrong owner was accepted';
EXCEPTION WHEN insufficient_privilege THEN
  NULL;
END $$;

SELECT job_id, job_status FROM vido.enqueue_searchy_job(
  decode(repeat('ab', 32), 'hex'), 42, -10042, NULL, 7, 'callback:1'
) \gset job_
RESET ROLE;

UPDATE vido.bridge_jobs SET
  status = 'ready',
  activity_stage = 'uploading_video',
  delivery_plan = jsonb_build_object(
    'version', 1,
    'job_id', :job_job_id,
    'activity_stage', 'uploading_video',
    'operations', jsonb_build_array(jsonb_build_object(
      'operation_id', 'media-1',
      'type', 'video',
      'source', jsonb_build_object(
        'kind', 'telegram_file_id',
        'value', 'fixture-file-id'
      ),
      'buttons', jsonb_build_array(jsonb_build_object(
        'type', 'audio', 'token', repeat('A', 32), 'text', 'Audio'
      ))
    ))
  ),
  ready_at = now()
WHERE id = :job_job_id;

SET ROLE searchy_core;
SELECT job_id, delivered_operation_ids
FROM vido.claim_searchy_delivery('searchy-test', 120) \gset delivery_
SELECT vido.begin_searchy_operation(
  'searchy-test', :delivery_job_id, 'media-1', 'video'
) AS begun \gset
\if :begun
\else
  \quit 1
\endif
SELECT vido.ack_searchy_operation(
  'searchy-test', :delivery_job_id, 'media-1', 'video', 88,
  '{}'::jsonb, jsonb_build_array(jsonb_build_object(
    'content_key', repeat('c', 64),
    'variant_key', repeat('d', 64),
    'send_kind', 'video',
    'item_index', 0,
    'file_id', 'fixture-file-id',
    'file_unique_id', 'fixture-unique-id'
  ))
) AS acked \gset
\if :acked
\else
  \quit 1
\endif
SELECT vido.finish_searchy_delivery('searchy-test', :delivery_job_id) AS finished \gset
\if :finished
\else
  \quit 1
\endif

DO $$
BEGIN
  PERFORM count(*) FROM vido.bridge_jobs;
  RAISE EXCEPTION 'searchy_core read a private table';
EXCEPTION WHEN insufficient_privilege THEN
  NULL;
END $$;
RESET ROLE;

SELECT EXISTS (
  SELECT 1 FROM vido.telegram_file_refs
   WHERE file_id = 'fixture-file-id'
     AND plan_template #>> '{operations,0,buttons,0,token}' = repeat('_', 32)
     AND plan_template::text NOT LIKE '%' || repeat('A', 32) || '%'
) AS token_redacted \gset
\if :token_redacted
\else
  \quit 1
\endif

SELECT EXISTS (
  SELECT 1 FROM vido.bridge_jobs
   WHERE id = :job_job_id AND status = 'delivered'
     AND source_url IS NULL AND delivery_plan IS NULL
) AS clean \gset
\if :clean
\else
  \quit 1
\endif
