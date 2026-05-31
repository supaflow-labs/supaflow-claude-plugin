# Supaflow MCP Workflows

These are the authoritative Desktop MCP workflows. Slash command files are CLI fallback/reference material only. If a workflow here intentionally differs from a command file, follow this file in Desktop MCP mode.

## Create pipeline

Use for: "create pipeline", "sync source to destination", "build a pipeline". This is the Desktop MCP replacement for the host-file editing parts of `/create-pipeline`.

1. Run the setup gate. Continue only after `mcp__supaflow__auth_status` passes.
2. Identify source datasource and destination project:
   - Call `mcp__supaflow__datasources_list` with `limit: 200`.
   - Resolve the source and destination by `name`, `api_name`, or `id`.
   - Capture source `id` and `api_name`; capture destination `id` and `api_name`.
   - Call `mcp__supaflow__projects_list`; match the destination by `warehouse_datasource_id`, not by name.
   - If no project exists for the destination id, create a project only after explicit confirmation, then re-read `projects_list`.
3. Run the duplicate-prevention gate before preparing config:
   - Page `mcp__supaflow__pipelines_list` with `limit: 200` and increasing `offset` until all pages are exhausted.
   - Compare each pipeline's `source.datasource_id` to the source id and `destination.datasource_id` to the destination id.
   - If a matching pipeline exists, show its name, api_name, state, source, destination, and project; call `mcp__supaflow__pipelines_schema_list` with `all: true`; report selected/excluded counts.
   - Then ask exactly one question: edit/use the existing pipeline, add objects to it, or create a separate pipeline.
   - If the user chooses a separate pipeline, warn that it uses a separate pipeline prefix and writes to a separate destination schema; require explicit confirmation before continuing.
4. Ask for the pipeline name. Suggest a source-to-destination name, but do not create yet.
5. Run `mcp__supaflow__pipelines_prepare_create` with the resolved source and project. Do not use raw `pipelines_init` plus file edits in Desktop mode.
6. Present the returned `config_summary`, `object_count`, and relevant `objects_preview`. State that the full object catalog is stored in the MCP plan and does not need cowork-VM file editing. State that `pipeline_prefix` cannot be changed after creation.
7. Ask for config changes one at a time. Represent approved changes as `config_patch`; do not create yet.
8. If the user changes `pipeline_prefix`, or proposes a custom prefix before final confirmation, run a typo check against the source datasource name, source api_name, source connector name/type, and the current prefix. If it looks like a misspelling, ask one confirmation question before accepting it because the prefix is permanent.
9. After every approved config change, re-present the full final config summary: `pipeline_prefix`, `ingestion_mode`, `load_mode`, `schema_evolution_mode`, `perform_hard_deletes`, `full_sync_frequency`, and `error_handling`. Do not treat a config edit as approval to create.
10. Ask the required object-scope question: all discovered objects or a subset.
11. If the user chooses all objects, use `object_selection: { "mode": "all" }`. This is valid even when `objects_truncated` is true because the MCP plan file contains the full catalog and the wrapper passes the prepared object file internally; do not try to translate this back into raw CLI `--objects` omission.
12. If the user chooses a subset, ask which objects to include. The user's answer is an include list, not an exclude list.
13. For subset selection:
   - Accept only fully qualified object names returned in `objects_preview`, or exact fully qualified names the user provides.
   - If `objects_truncated` is true and the needed names are not visible in `objects_preview`, tell the user to review the host-side `host_files.objects` file outside chat and provide the exact `fully_qualified_name` values to include. Do not paste the full file into chat.
   - If the user cannot provide exact fully qualified names from the host file, ask whether to select all objects instead. Otherwise STOP and explain that a plan-object search/page helper is needed before safely choosing from the hidden catalog.
   - Never invent object names or infer names from partial table labels.
14. Present final confirmation with pipeline name, source, project, destination, config summary, and object scope. Wait for explicit confirmation. The object-scope answer alone is not final approval.
15. Call `mcp__supaflow__pipelines_create_from_plan` with:
   - `plan_id` from prepare,
   - `name`,
   - `confirmed: true`,
   - `config_patch`,
   - `object_selection: { "mode": "all" }` or `{ "mode": "subset", "include": [...] }`.
16. Report the returned `pipeline`, `object_selection`, and `verification`. Trust `verification` over the create-response summary if they differ. If `verification.status` is not `verified`, say creation succeeded but verification did not complete and show `verification.error`.

Never call `pipelines_create_from_plan` before final confirmation. Never invent object names; subset names must come from the prepared object list.

## Check job status

Use for: "check job", "latest sync", "is the pipeline done", "what happened to job X".

1. Run the setup gate. Continue only after `mcp__supaflow__auth_status` passes.
2. Resolve the input:
   - If the input is a UUID, treat it as the job id.
   - If the input is not a UUID, call `mcp__supaflow__pipelines_list` with `limit: 200`, match by `name`, `api_name`, or `id`, then call `mcp__supaflow__jobs_list` with `filter: ["pipeline=<pipeline-id>"]` and `limit: 1`.
   - If the list result is truncated (`total > data.length`) and no match was found, page with `offset` before saying not found.
3. Call `mcp__supaflow__jobs_status` with the resolved job id.
4. Parse only `id`, `job_status`, `status_message`, and `job_response`.
5. If the status is terminal and the user asked for details or results, call `mcp__supaflow__jobs_get`. Parse only `execution_duration_ms`, `ended_at`, `job_response`, and `object_details`.
6. Report only fields that exist in the returned JSON. Do not invent `duration`, `completed_at`, `objects`, `rows_read`, `progress`, or `eta`.

Terminal statuses: `completed`, `completed_with_warning`, `failed`, `cancelled`, `timed_out`.

## Explain job failure

Use for: "why did this job fail", "diagnose job X", "explain the failed sync".

1. Run the setup gate. Continue only after `mcp__supaflow__auth_status` passes.
2. Call `mcp__supaflow__jobs_get` for the job id.
3. Identify failed objects using only `object_details[].ingestion_status`, `object_details[].staging_status`, `object_details[].loading_status`, and `fully_qualified_source_object_name`.
4. Call `mcp__supaflow__jobs_logs` for the same job id.
5. Extract the relevant error lines from the returned log text. Do not paste the full log.
6. Report: what failed, which stage failed, the exact root-cause line if present, and the recommended next action.

Do not offer to retry until the root cause has been identified and communicated. If the root cause is unclear, say so and recommend the narrowest diagnostic action.
