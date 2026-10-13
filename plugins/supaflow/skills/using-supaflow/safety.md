# Hosted MCP safety

These rules apply to the hosted connection only. It has no local-file exports, credential files, or private-agent lifecycle tools. Consult each loaded tool's actual input schema before calling it.

## Read, authorize, call, verify

1. Resolve the workspace and read the exact resource before a mutation. Prefer a get operation for a known ID.
2. Explain the requested change, target, and impact. A specific user request can authorize an ordinary normal sync or reversible edit; do not infer unrelated changes from it.
3. For creation, show the final actual configuration and scope, then get explicit approval. For deletion, `jobs_cancel`, `datasources_reset_catalog`, and any `pipelines_sync` with `full_resync: true` or `reset_target: true`, obtain explicit confirmation immediately before the call.
4. Call only the authorized operation and pass the selected `workspace_id`. Never change tools or targets to get around an authorization error.
5. Re-read the target or monitor the returned job ID. Report verified state; an enqueue acknowledgement is not job completion.

## Destructive and maintenance actions

- Deletes: resolve and display the exact datasource, pipeline, project, or schedule. Explain dependent-resource impact returned by the service. Confirm before calling the corresponding delete operation.
- Cancellation: read `jobs_status`, continue only for a `queued`, `picked`, or `running` job, show its ID/state, explain the processing interruption, and confirm before `jobs_cancel`. Re-read the status afterward.
- Full resync: explain that cursors are reset and all selected data is reread. A target reset also drops/recreates destination tables; it requires full resync. Confirm the exact pipeline and selected scope before either flag is true.
- Catalog reset: explain that existing pipelines and selections are preserved, affected activity is temporarily paused, and rediscovery may change cursor/type/schema behavior. After `datasources_reset_catalog`, poll `datasources_catalog_reset_status` until the returned `catalog_reset.maintenance_active` is false, even if the job has already become terminal. Then reread the catalog and affected pipeline selections. Stop and report a failed restoration rather than claiming success.
- Tests, schema refreshes, and normal syncs return job IDs for job monitoring; preserve the returned ID. Schedule runs return only a trigger acknowledgement: resolve the new execution through `schedules_history` as described in the schedules skill. Monitor that execution's history, and use job tools only for an explicitly associated job ID. Never reinterpret a schedule or execution ID as a job ID, or repeat the trigger because history is delayed or ambiguous.

## Credential and output hygiene

Never ask users to paste secrets into chat or fabricate encrypted envelopes. New credentials and connector OAuth should be configured in Supaflow or through an approved encrypted channel. Prefer `copy_from_identifier` for an explicitly authorized server-side copy of an accessible datasource. Hosted datasource get/list results do not expose credential configs.

Summarize safe identifiers, names, states, counts, and relevant error text. Redact sensitive material if it appears in logs or a returned error; do not dump full payloads or signed plan IDs into the conversation. A signed plan is short-lived, identity-bound and workspace-bound; do not reuse it after an account/workspace change or expiry.

## Ambiguous outcomes

Never blindly repeat create, edit, sync, refresh, test, reset, schedule-run, delete, or cancel operations after a timeout or uncertain transport error. Reconcile using the matching get/list operation or `jobs_list` for the same workspace/pipeline. Repeat only when current state proves the first operation did not take effect and the user's authorization still applies. Otherwise report the uncertainty and ask for direction.
