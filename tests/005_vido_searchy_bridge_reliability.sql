\set ON_ERROR_STOP on

-- ACK response loss must never downgrade a delivered operation.
SET ROLE searchy_core;
SELECT vido.create_download_intent(
  decode(repeat('cd', 32), 'hex'),
  43, 'video', 'searchy_chat', 'https://example.com/watch/43',
  'other', 'searchy_chat', now() + interval '6 hours', -10043,
  'reliability', 'Reliable', NULL, 'en', NULL
);
SELECT vido.bind_intent_message(decode(repeat('cd', 32), 'hex'), 43, -10043, 43);
SELECT job_id FROM vido.enqueue_searchy_job(
  decode(repeat('cd', 32), 'hex'), 43, -10043, NULL, 43, 'callback:ack-loss'
) \gset ack_
RESET ROLE;

UPDATE vido.bridge_jobs SET status = 'ready', activity_stage = 'uploading_video',
  delivery_plan = jsonb_build_object(
    'version', 1, 'job_id', :ack_job_id, 'activity_stage', 'uploading_video',
    'operations', jsonb_build_array(jsonb_build_object(
      'operation_id', 'media-1', 'type', 'video',
      'source', jsonb_build_object('kind', 'telegram_file_id', 'value', 'ack-file')
    ))
  ), ready_at = now()
WHERE id = :ack_job_id;

SET ROLE searchy_core;
SELECT job_id FROM vido.claim_searchy_delivery('ack-worker', 120) \gset claimed_
SELECT vido.begin_searchy_operation('ack-worker', :claimed_job_id, 'media-1', 'video') AS begun \gset
SELECT vido.ack_searchy_operation(
  'ack-worker', :claimed_job_id, 'media-1', 'video', 430,
  '{}'::jsonb, '[]'::jsonb
) AS acked \gset
SELECT vido.fail_searchy_operation(
  'ack-worker', :claimed_job_id, 'media-1', 'video', 'ack_unknown', true
) AS stale_fail \gset
SELECT vido.finish_searchy_delivery('ack-worker', :claimed_job_id) AS finished \gset
\if :begun
\else
  \quit 1
\endif
\if :acked
\else
  \quit 1
\endif
\if :stale_fail
\else
  \quit 1
\endif
\if :finished
\else
  \quit 1
\endif
RESET ROLE;

SELECT EXISTS (
  SELECT 1 FROM vido.delivery_operations
   WHERE job_id = :claimed_job_id AND operation_id = 'media-1'
     AND status = 'delivered'
) AS delivered_not_downgraded \gset
\if :delivered_not_downgraded
\else
  \quit 1
\endif

-- A stale "sending" operation becomes delivery_unknown and is never claimed
-- for automatic replay. The durable notification yields an owner-bound token.
SET ROLE searchy_core;
SELECT vido.create_download_intent(
  decode(repeat('ef', 32), 'hex'),
  44, 'video', 'searchy_chat', 'https://example.com/watch/44',
  'other', 'searchy_chat', now() + interval '6 hours', -10044,
  'unknown', 'Unknown', NULL, 'en', NULL
);
SELECT vido.bind_intent_message(decode(repeat('ef', 32), 'hex'), 44, -10044, 44);
SELECT job_id FROM vido.enqueue_searchy_job(
  decode(repeat('ef', 32), 'hex'), 44, -10044, NULL, 44, 'callback:unknown'
) \gset unknown_
RESET ROLE;

UPDATE vido.bridge_jobs SET status = 'ready', activity_stage = 'uploading_video',
  delivery_plan = jsonb_build_object(
    'version', 1, 'job_id', :unknown_job_id, 'activity_stage', 'uploading_video',
    'operations', jsonb_build_array(jsonb_build_object(
      'operation_id', 'media-1', 'type', 'video',
      'source', jsonb_build_object('kind', 'telegram_file_id', 'value', 'unknown-file')
    ))
  ), ready_at = now()
WHERE id = :unknown_job_id;

SET ROLE searchy_core;
SELECT job_id FROM vido.claim_searchy_delivery('dead-worker', 30) \gset dead_
SELECT vido.begin_searchy_operation('dead-worker', :dead_job_id, 'media-1', 'video');
RESET ROLE;
UPDATE vido.bridge_jobs SET lease_expires_at = now() - interval '1 second'
 WHERE id = :dead_job_id;

SET ROLE searchy_core;
SELECT count(*) AS replay_claims FROM vido.claim_searchy_delivery('new-worker', 30) \gset replay_
\if :replay_replay_claims
  \quit 1
\endif
SELECT job_id, job_status, retry_token
  FROM vido.claim_searchy_notification('notify-worker', 120) \gset notice_
SELECT vido.ack_searchy_notification(
  'notify-worker', :notice_job_id, :'notice_job_status'
) AS notice_acked \gset
\if :notice_acked
\else
  \quit 1
\endif
SELECT * FROM vido.enqueue_searchy_retry_job(
  public.digest(:'notice_retry_token', 'sha256'), 44, -10044, NULL, 44, 'retry:1'
) \gset retried_
SELECT (:retried_job_id::bigint = :unknown_job_id::bigint) AS retried_same_job \gset
\if :retried_same_job
\else
  \quit 1
\endif
SELECT * FROM vido.enqueue_searchy_retry_job(
  public.digest(:'notice_retry_token', 'sha256'), 44, -10044, NULL, 44, 'retry:2'
) \gset replayed_retry_
SELECT (:replayed_retry_job_id::bigint = :unknown_job_id::bigint) AS replayed_same_job \gset
\if :replayed_same_job
\else
  \quit 1
\endif
RESET ROLE;

SELECT EXISTS (
  SELECT 1 FROM vido.bridge_jobs
   WHERE id = :unknown_job_id AND status = 'queued'
) AS explicit_retry_queued \gset
\if :explicit_retry_queued
\else
  \quit 1
\endif

-- PUBLIC cannot execute the newly added bridge API.
SELECT NOT has_function_privilege(
  'public', 'vido.begin_searchy_operation(text,bigint,text,text)', 'EXECUTE'
) AS public_blocked \gset
\if :public_blocked
\else
  \quit 1
\endif
