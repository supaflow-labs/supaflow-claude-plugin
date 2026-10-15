---
name: supaflow-pipelines
description: Discover, inspect, create, edit, delete, and sync Supaflow pipelines using hosted MCP. Use when the user asks to move data between a source and destination, review selected objects, or run a pipeline.
---

# Hosted pipelines

Follow [the connection/workspace gate](../using-supaflow/SKILL.md), [safety rules](../using-supaflow/safety.md), and [response contracts](../using-supaflow/response-contracts.md). Every call below includes the resolved `workspace_id`.

## Discover and inspect

- Use `pipelines_list` for discovery and `pipelines_get(identifier)` for a known pipeline. Match actual names/IDs, ask if ambiguous, and use the returned ID thereafter.
- Hosted metadata uses `sourceDatasourceId`, `sourceName`, `destinationDatasourceId`, `destinationName`, `projectId`, and `projectName`. Do not apply the local command's nested source/destination contract.
- Use `pipelines_schema_list` for selected objects. Advance offset by limit while `has_more` is true, even if `objects` is empty or shorter than limit; selected objects can be sparse across a large catalog. Keep `all: false` unless the user needs deselected objects. Use `with_fields: true` when reviewing or editing field selection.
- For a complete selection, start at offset 0 and keep one fixed limit and the same workspace, pipeline, and filters throughout. After each response, the only next offset is the current offset plus that limit. For limit 200 the requests must be 0, 200, 400, 600, 800, 1000, 1200, and so on, stopping at the first response with `has_more: false`. Do not jump ahead, probe a distant offset, binary-search the catalog end, or infer completion from finding the expected object names. A false response from a distant probe does not prove that intervening pages were read. If interrupted, report a partial inventory rather than claiming completeness.
- When only object names are requested, use `with_fields: false` to avoid oversized field responses. Do not fetch unrelated catalogs or jobs to discover a pagination boundary; the schema response's `has_more` is sufficient.
- Report only the saved metadata and object selection returned. Full saved configuration is not exposed by `pipelines_get`; say so rather than substituting new-pipeline defaults from `pipelines_init`.

## Create a pipeline

1. Discover existing `datasources_list` and `projects_list` results. Resolve the source and destination by their actual IDs and active states; match an existing project's `destinationDatasourceId` to the destination ID. Create a project only after reviewing its destination/name and obtaining explicit approval; then reread it.
2. Traverse `pipelines_list` before preparing a new pipeline. Detect duplicates using `sourceDatasourceId` and `destinationDatasourceId`. If one exists, show it and its selected objects; ask whether to use/edit it or intentionally create a separate pipeline. Never silently rename or duplicate after a constraint error.
3. Resolve the pipeline name and ensure the source catalog has been discovered. Read it with `datasources_catalog(refresh: false)`; any refresh requires separate authorization and job monitoring.
4. Call `pipelines_prepare_create(source, project)`. The result is a short-lived signed plan, not a file on the user's machine. Present the actual `config`, `object_count_total`, `objects_preview`, and `object_preview_truncated` values.
5. Ask for config changes and represent approved changes in `config_patch`. Re-present the full final configuration after edits. If a custom prefix looks misspelled, confirm it explicitly. Prefix changes are allowed only while a pipeline is draft; after activation, the existing prefix is retained.
6. Ask whether to select all discovered objects or a subset. For all, use `object_selection: { "mode": "all" }` even if the preview is truncated. For a subset, treat the answer as an include list, not an exclude list. Page `datasources_catalog` to resolve exact `fully_qualified_name` values outside the preview; never invent names or ask the user to open nonexistent plan files.
7. Show the final name, workspace, source, destination/project, actual config plus patch, and object scope. Obtain explicit final approval; a config edit or object-selection answer alone is not creation approval.
8. Call `pipelines_create_from_plan` with `plan_id`, name, `config_patch`, object scope, and `confirmed: true` only after that final approval. Do not reuse an expired or different-user/workspace plan; prepare and review a fresh plan if required.
9. Reread `pipelines_get` and the complete selected-object pages. If verification fails, report creation as unverified rather than repeating it. Do not automatically sync or schedule the new pipeline.

## Edit and delete

- Before `pipelines_edit`, read the target, show the exact supported patch, obtain authorization for those changes, and reread metadata. Do not claim to verify full saved config when the get result lacks it.
- Before `pipelines_schema_select` or `pipelines_schema_add`, read current selection/fields, resolve exact catalog names, preserve fields not being changed, show the proposed selection changes, and obtain approval. Verify complete selected-object pages afterward.
- Before `pipelines_delete`, show the exact name/ID and scope, explain the deletion, and obtain explicit confirmation immediately before the call. Verify the live deleted state or complete inventory; do not mistake a missing first-page entry for deletion.

## Run one normal sync and monitor

1. Read `pipelines_get` and resolve the exact pipeline in the chosen workspace. A clear user request to run that pipeline with a normal sync authorizes one run; otherwise ask for the intended run.
2. Call `pipelines_sync` once with `identifier`, `workspace_id`, `full_resync: false`, and `reset_target: false`. Do not edit config, expand object scope, or change schedules as part of a normal sync.
3. Capture `job_id` from the enqueue response. Poll `jobs_status` for that same ID, then use `jobs_get` and `jobs_logs` for terminal details as specified by the jobs skill.
4. If the response is ambiguous, reconcile with `jobs_list(pipeline_id)` before any further mutation. Do not blindly repeat the sync or switch to a second execution surface.
5. A failed terminal job is a completed monitoring task, not a successful sync. Report the actual root-cause message; do not retry until the cause and the user's next action are clear.

For `full_resync: true` or `reset_target: true`, explain cursor reset and target-table destruction, confirm the exact pipeline/scope immediately before the call, and require full resync for target reset. Never turn these flags on as an automatic failure-recovery step.
