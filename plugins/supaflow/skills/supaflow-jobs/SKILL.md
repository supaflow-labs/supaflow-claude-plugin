---
name: supaflow-jobs
description: List, inspect, monitor, diagnose, and safely cancel Supaflow jobs through hosted MCP. Use when the user asks for recent jobs, sync progress, final row metrics, warnings, or failure details.
---

# Hosted jobs

Follow [the connection/workspace gate](../using-supaflow/SKILL.md), [safety rules](../using-supaflow/safety.md), and [response contracts](../using-supaflow/response-contracts.md). Every job call includes the resolved `workspace_id`.

## Resolve the job

- Prefer the exact `job_id` returned by the operation being monitored. It is not a pipeline ID.
- For a pipeline name, resolve it through `pipelines_get`/`pipelines_list`, then call `jobs_list(pipeline_id: resolved_id, limit: 1)`. For five recent jobs, request `limit: 5`; the returned `jobs` are newest first.
- Do not count jobs as pipelines. A pipeline can have many historical runs, and datasource test/discovery jobs are separate job types.
- Report only available start/end times, durations, states, and IDs. `jobs_list` does not return per-object row counts; obtain terminal details if needed or say the count is unavailable.

## Monitor an existing job

1. Call `jobs_status(id)` and read `job.status` and `job.statusMessage`. Hosted polling is wrapped in `job`; it does not use the local command's `job_status` field.
2. Continue while the job is nonterminal, normally with about 30 seconds between polls using the host's supported waiting mechanism. Keep the user informed during a long run. Do not launch another job, use a local shell for polling, or interpret unchanged state as failure.
3. Terminal states are `completed`, `completed_with_warning`, `failed`, `cancelled`, `timed_out`, and `skipped`. Once terminal, call `jobs_get(id)` before the final summary. Use `jobs_logs(id)` for stored response metrics and warning/error detail. A skipped job has finished without executing the requested work: report its returned reason and available details, stop polling, and do not automatically rerun or attempt recovery.
4. Report `job.startedAt`, `job.endedAt`, and `job.executionDurationMs` only when returned. Preserve a recorded zero duration; missing duration is not zero.
5. `jobs_get` returns `job.object_details`; object names use `fully_qualified_source_object_name`, stage states use `ingestion_status`, `staging_status`, `loading_status`, and stage metrics may include `ingestion_metrics.output_row_count`. Do not invent rows or metrics for objects with no details.
6. `jobs_logs` returns `job.response`, which may be null. Include totals such as `total_rows_source` or `total_rows_destination` only if actually present there. Missing row counts are unavailable, not zero; an empty details list alone does not prove that zero rows were processed.
7. If the host's monitoring window ends before a terminal state, report the job ID and last observed state as still running/queued. Continuing later means polling that same ID, not starting a new sync.

Retry failed read calls only when the returned error explicitly says `retryable: true`, respecting `retry_after_ms` and a bounded number of attempts. Stop on authorization, validation, and not-found errors; do not disguise them as transient job states.

## Diagnose failure

Read `jobs_get` and `jobs_logs` for the same job ID. Describe the actual status message, failing object/stage, and relevant redacted response detail. `jobs_logs` is a stored control-plane response, not access to private-agent filesystem logs. Null response means no further stored detail is available; do not infer a missing error message or claim to read local logs.

Explain the narrowest next action. Do not automatically rerun, reset the destination, refresh a catalog, change credentials, or cancel another job.

## Cancel

Read the exact `jobs_status` first and continue only for `queued`, `picked`, or `running`. Show the job's ID, state, and processing interruption, obtain explicit confirmation immediately before `jobs_cancel`, then reread status and report the verified state. Host `Always allow` or a tool approval click does not replace that confirmation.
