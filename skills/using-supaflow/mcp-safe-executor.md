# Supaflow MCP Safe Executor

Read this before calling any `mcp__supaflow__*` tool that changes host state, workspace state, files, datasources, pipelines, schedules, jobs, or object selections.

## Tool classes

Workflow read-only calls: `auth_status`, `workspaces_list`, `connectors_list`, `datasources_list`, `datasources_get` without `output_file`, `datasources_catalog` without `output_file` or `refresh`, `pipelines_list`, `pipelines_get`, `pipelines_schema_list`, `projects_list`, `jobs_list`, `jobs_status`, `jobs_get`, `jobs_logs`, `schedules_list`, `schedules_history`, `docs` without `output_file` or `refresh`.

MCP annotations are per tool, not per argument. Tools that can write host files or refresh data are annotated conservatively even when a specific call is workflow-read-only.

Host-file tools: `datasources_get` with `output_file`, `datasources_catalog` with `output_file`, `docs` with `output_file`, `datasources_init`, `pipelines_init`, `pipelines_prepare_create`. These write to the host filesystem where the MCP server runs. Use explicit host paths and tell the user which path is being written. `pipelines_prepare_create` also calls `datasources catalog`; set `refresh_catalog: true` only after the user explicitly asks to refresh the source catalog.

Claude Desktop cowork-VM file tools may not be able to read or edit those host paths. If a workflow requires editing a host-generated env/config/object file and no dedicated MCP tool performs that exact edit, STOP and ask the user to edit the host file themselves or switch to a terminal CLI session. Do not claim the file was edited unless a tool actually edited the host file.

Workspace- or host-mutating tools: `workspaces_select`, `datasources_create`, `datasources_edit`, `datasources_test`, `datasources_enable`, `datasources_disable`, `datasources_refresh`, `pipelines_create_from_plan`, `pipelines_create`, `pipelines_edit`, `pipelines_schema_select`, `pipelines_schema_add`, `pipelines_enable`, `pipelines_disable`, `pipelines_sync`, `projects_create`, `schedules_create`, `schedules_edit`, `schedules_enable`, `schedules_disable`, `schedules_run`, `agent_start` (never with `approve: true` unless the user explicitly asked -- approval switches the tenant's job routing to the new agent), `agent_stop`.

Destructive tools: `datasources_delete`, `pipelines_delete`, `schedules_delete`, `agent_remove` (always -- it force-removes the container; with `purge: true` it also deletes the agent identity volume, so the next start enrolls a brand-new agent), `agent_upgrade` (CLI/MCP 0.5.0+; stops and replaces the current container but preserves the identity volume and attempts rollback), and `pipelines_sync` when `reset_target: true`.

Credential-bearing outputs: `datasources_get`, env-file exports, and some logs can include `configs`, encrypted secret blobs, token-like values, or other credential-shaped data. Never paste those values into chat. When reporting datasource details, use only safe fields: `name`, `api_name`, `id`, `state`, `connector_name`, `connector_type`, project linkage, counts, and non-secret capability summaries.

That rule is about **chat hygiene, not disk hygiene**. Sensitive datasource fields are stored encrypted -- a `BEFORE INSERT OR UPDATE` trigger (`encrypt_datasource_config`) encrypts them server-side, and the CLI holds no decryption key. So `datasources_get` returns `enc:` envelopes, and `output_file` exports write those same envelopes. Writing an env-file export to disk is safe and is the intended way to edit a datasource: **do not refuse `output_file` on secret-hygiene grounds.** What you must not do is echo envelopes (or key fingerprints) into the transcript, because the transcript is durable and the blobs are noise.

## Required sequence for every non-read-only MCP call

1. Read current state first with the narrowest read-only tool that proves the target exists.
2. Present the exact operation in plain language, including workspace, target name/api_name/id, changed fields, file path if any, and blast radius.
3. Ask exactly one confirmation question and wait. Do not infer approval from edits, object-scope answers, or MCP's own approval prompt.
4. Call the mutating MCP tool only after explicit user confirmation.
5. Re-read state after the tool call and report verified live state, not assumptions.

## Additional hard gates

- In Desktop MCP mode, prefer `mcp__supaflow__pipelines_prepare_create` then `mcp__supaflow__pipelines_create_from_plan` for pipeline creation. Do not use raw `mcp__supaflow__pipelines_create` unless the user explicitly asks for the low-level tool.
- Before `mcp__supaflow__pipelines_create_from_plan`: present `config_summary`, object count/preview, final config changes, and object scope from the prepared plan; require final explicit confirmation; pass `confirmed: true` only after that confirmation.
- Before raw `mcp__supaflow__pipelines_create`: follow the full pipeline creation workflow from `commands/create-pipeline.md`; run `pipelines_init`; present actual config values; require object-scope choice; require final explicit confirmation.
- Before `mcp__supaflow__pipelines_schema_select`: read the current selected schema with `pipelines_schema_list(with_fields:true)` unless the user explicitly needs currently deselected objects. Use `all:true` only for bulk-adding deselected objects because it scans the full catalog. Edit only the selected/field flags requested by the user, show selected counts, then confirm.
- Before `mcp__supaflow__pipelines_sync` with `full_resync` or `reset_target`: state whether cursors reset and whether destination tables are dropped/recreated; require explicit confirmation.
- Before any delete: show the resolved target details and ask the user to confirm deletion by name or with an unambiguous yes. MCP approval alone is not confirmation.
- Before `mcp__supaflow__agent_upgrade`: call `agent_status`, show the container name and requested image, explain the brief interruption, and get explicit confirmation. Use `pull: false` only when the user explicitly asks to install an image already present locally. Afterward, call `agent_status` again to verify the replacement is running and still maps to the expected agent identity.
- After any sync trigger: capture `job_id`; if polling, use `jobs_status` only for polling; once terminal, call `jobs_get` before giving the final result.

## Error handling

If a mutating tool returns an error, STOP. Show the error text verbatim. Do not retry with a different name, prefix, target, object list, cron, or config unless the user explicitly chooses that correction after seeing the error.
