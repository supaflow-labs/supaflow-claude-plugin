# Hosted response contracts

These are hosted MCP contracts, not CLI JSON contracts. Inspect actual responses and the loaded input schema; do not substitute fields from another execution surface. Use structured results when available; otherwise parse the JSON text result. An error or `isError` result is not successful data.

| Operation | Response |
| --- | --- |
| `auth_status` | `authenticated`, `user_id`, `organization_id`, `workspaces` |
| `workspaces_list` | `workspaces` |
| `connectors_list` | `connectors` with `type`, `name`, `version`, `capabilities` |
| `datasources_list` | `datasources`, `total`, `limit`, `offset`; items include `id`, `name`, `apiName`, `connectorType`, `connectorName`, `state` |
| `datasources_get` | `datasource`; safe metadata, not credential configs |
| `projects_list` | `projects`, `total`, `limit`, `offset`; items include `destinationDatasourceId` |
| `pipelines_list` | `pipelines`, `total`, `limit`, `offset`; items include `sourceDatasourceId`, `sourceName`, `destinationDatasourceId`, `destinationName`, `projectId`, `projectName`, `state` |
| `pipelines_get` | `pipeline`; safe metadata, not the full pipeline config |
| `pipelines_init` | `source`, `project`, `destination`, `config`; defaults for a new pipeline, not the saved config of an existing pipeline |
| `pipelines_prepare_create` | `plan_id`, `config`, `objects_preview`, `object_count_returned`, `object_count_total`, `object_preview_truncated`, `expires_in_seconds`, `source`, `project`, `destination` |
| `pipelines_create_from_plan` | `pipeline`; re-read metadata and selected objects to verify creation |
| `pipelines_schema_list` | `pipeline_id`, `objects`, `limit`, `offset`, `has_more`; each object has `fully_qualified_name`, `selected`, `fields` |
| `datasources_catalog` | `datasource_id`, `objects`, `limit`, `offset`, `refresh_job_id`; names are `fully_qualified_name` |
| `pipelines_sync` | `job_id`, `pipeline_id`, `status` (enqueue status) |
| `jobs_list` | `jobs`, `total`, `limit`, `offset`; newest first; filter with input `pipeline_id`, `status`, or `type` |
| `jobs_status` | `job.id`, `job.status`, `job.statusMessage`, `job.updatedAt` |
| `jobs_get` | `job` with `status`, `statusMessage`, `startedAt`, `endedAt`, `executionDurationMs`, and `object_details` |
| `jobs_logs` | `job.id`, `job.status`, `job.response`; stored control-plane response, not local filesystem logs; `response` can be null |
| `schedules_list` | `schedules`, `total`, `limit`, `offset`; items use `cron_schedule`, `timezone`, `target_type`, `target_id`, `state` |
| `schedules_create` | `schedule` with `id`, `name`, `cron`, target and state; verify using `schedules_list` |
| `schedules_run` | `schedule.id`, `schedule.status: "triggered"`; no job ID; resolve the new execution before monitoring |
| `schedules_history` | `schedule_id`, `executions`; rows contain execution metadata such as `execution_id`, `triggered_at`, `completed_at`, `status`, `duration`, entry counts and `error_message`; a job-ID association is not guaranteed |

## Pagination

- For inventory traversals, use a supported page size up to 200. If the loaded `datasources_list`/`pipelines_list` schema advertises `sort` and `after_id`, use `sort: "id"` and the last returned ID as `after_id` until an empty page. Do not mix cursor and offset modes. This is a live traversal, not a database snapshot.
- Otherwise use `offset` pages and the returned `total`; advance by the requested `limit`, report truncation, and do not claim a complete inventory from one partial page. For known IDs, prefer get operations. Reconcile concurrent changes rather than relying on old totals.
- For `pipelines_schema_list`, offsets address the full catalog before selected-object filtering. Advance offset by limit while `has_more` is true, even if `objects` is empty or shorter than limit. Stop only when `has_more` is false. Do not use selected-row counts as the page-completion signal.
  Start at offset 0 with a fixed limit. Process requests sequentially: wait for the current page, collect its selected objects, then request exactly `current offset + limit` if `has_more` is true. Preserve workspace, pipeline, and filter arguments. Never jump, binary-search, or probe far ahead to locate the last page. A distant empty page with `has_more: false` is not evidence that skipped pages contained no selections. If the traversal cannot finish, label the selection incomplete. Request fields only when needed; object-name inspection uses `with_fields: false`.
- For `datasources_catalog`, the page is unfiltered: continue until a page contains fewer than limit objects, or use its actual completion field if the loaded server exposes one. Do not invent a `total` or `has_more` field.

## Missing fields

Do not invent saved pipeline configuration, refresh mode, progress, ETA, row totals, or success counts. `pipelines_get` exposes metadata, not saved ingestion/load settings. Describe the source, destination, state, and selected objects, and say when full configuration is unavailable. Do not call `pipelines_init` to pretend its new-pipeline defaults are an existing pipeline's saved settings.

For terminal metrics, use only returned `object_details` and `job.response` values. A missing or null row count is unavailable, not zero. A recorded duration of zero is valid; do not replace it with a guessed elapsed time.

A schedule trigger acknowledgement is not a job record. Schedule IDs and execution IDs are distinct from job IDs; never substitute them in job tools. Compare schedule history with a pre-trigger baseline and monitor the resolved execution by its actual ID. Use job polling only when a response explicitly supplies an associated job ID. If correlation is unavailable or ambiguous, report the monitoring limitation without guessing or retriggering.
