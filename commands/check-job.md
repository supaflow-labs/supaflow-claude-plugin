---
description: Check the status of a Supaflow job or the latest job for a pipeline
allowed-tools: Bash(supaflow *)
argument-hint: [job-id or pipeline-name]
---

# Check Supaflow Job Status

Check the status of a specific job by ID, or look up the latest job for a named pipeline.

## Setup Check

Run this first. If it fails, stop and tell the user what to fix before proceeding.

```bash
supaflow auth status --json | python3 -c "
import sys, json
d = json.load(sys.stdin)
if 'error' in d: print('ERROR: ' + d['error']['message']); sys.exit(1)
if not d.get('authenticated'): print('NOT AUTHENTICATED: Run supaflow auth login --key <api-key>'); sys.exit(1)
if not d.get('workspace_id'): print('NO WORKSPACE: Run supaflow workspaces select <name>'); sys.exit(1)
print('OK: authenticated as workspace ' + str(d.get('workspace_name', d['workspace_id'])))
"
```

If the check fails, STOP. Tell the user exactly what to fix (authentication or workspace selection). Do NOT attempt to install npm packages or run any commands other than `supaflow *`.

## Input Resolution

The argument is either a job UUID or a pipeline name/api_name.

**UUID (direct job lookup):** If the argument matches the UUID pattern (e.g., `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`), use it directly as the job ID.

**Non-UUID (pipeline name):** Resolve to a job ID via two steps:

Step 1 -- find the pipeline UUID by name:
```bash
supaflow pipelines list --json | python3 -c "
import sys, json
d = json.load(sys.stdin)
if 'error' in d: print('ERROR: ' + d['error']['message']); sys.exit(1)
name = '<PIPELINE_NAME>'
matches = [p for p in d.get('data', []) if p.get('name') == name or p.get('api_name') == name or p.get('id') == name]
if not matches: print('NOT FOUND: no pipeline named ' + repr(name)); sys.exit(1)
print(matches[0]['id'])
"
```

Step 2 -- get the latest job for that pipeline UUID:
```bash
supaflow jobs list --filter pipeline=<PIPELINE_UUID> --json --limit 1 | python3 -c "
import sys, json
d = json.load(sys.stdin)
if 'error' in d: print('ERROR: ' + d['error']['message']); sys.exit(1)
jobs = d.get('data', [])
if not jobs: print('NO JOBS: no jobs found for this pipeline'); sys.exit(1)
print(jobs[0]['id'])
"
```

## Status Check

Run `jobs status` with the resolved job ID. This command returns a lightweight payload (~100 bytes) suitable for polling.

```bash
supaflow jobs status <JOB_ID> --json | python3 -c "
import sys, json
d = json.load(sys.stdin)
if 'error' in d: print('ERROR: ' + d['error']['message']); sys.exit(1)
status = d['job_status']
msg = d.get('status_message') or ''
resp = d.get('job_response')
if resp:
    print(f\"Status: {status} | Objects: {resp.get('total_objects', 0)} | Rows: {resp.get('total_rows_source', 0)} src, {resp.get('total_rows_destination', 0)} dst | Failed: {resp.get('total_failed', 0)}\")
else:
    print(f\"Status: {status} | {msg}\")
"
```

**Parser contract for `jobs status`:** The command returns ONLY these 4 fields:
- `id` -- the job UUID
- `job_status` -- current status string
- `status_message` -- optional human-readable message
- `job_response` -- optional summary object with `total_objects`, `total_rows_source`, `total_rows_destination`, `total_failed`, `total_skipped`

NEVER reference these fields from `jobs status` output -- they do not exist:
- `phase`, `duration`, `completed_at`, `progress`, `percent`, `eta`

## Detailed View (Terminal States Only)

Only run `jobs get` after the job has reached a terminal state: `completed`, `completed_with_warning`, `failed`, or `cancelled`. Do NOT call `jobs get` while the job is still `pending` or `running`.

```bash
supaflow jobs get <JOB_ID> --json | python3 -c "
import sys, json
j = json.load(sys.stdin)
if 'error' in j: print('ERROR: ' + j['error']['message']); sys.exit(1)
dur = j.get('execution_duration_ms', 0)
print(f\"Status: {j['job_status']} | Duration: {dur}ms | Message: {j.get('status_message', '')}\")
resp = j.get('job_response') or {}
print(f\"Objects: {resp.get('total_objects', 0)} | Rows: {resp.get('total_rows_source', 0)} source, {resp.get('total_rows_destination', 0)} dest | Failed: {resp.get('total_failed', 0)}\")
for o in j.get('object_details', []):
    name = o['fully_qualified_source_object_name']
    rows = (o.get('ingestion_metrics') or {}).get('output_row_count', 0)
    print(f\"  {name}: ingestion={o['ingestion_status']} staging={o['staging_status']} loading={o['loading_status']} ({rows} rows)\")
"
```

**Parser contract for `jobs get`:** Use ONLY these fields:
- `id` -- the job UUID
- `job_status` -- terminal status string
- `status_message` -- optional human-readable message
- `execution_duration_ms` -- wall-clock duration in milliseconds
- `ended_at` -- ISO-8601 timestamp when the job finished
- `job_response` -- summary object (see `total_objects`, `total_rows_source`, `total_rows_destination`, `total_failed`, `total_skipped`)
- `object_details` -- array of per-object stage records

For each entry in `object_details`:
- Object name: `fully_qualified_source_object_name`
- Stage statuses: `ingestion_status`, `staging_status`, `loading_status`
- Row count: `ingestion_metrics.output_row_count`

NEVER reference these fields from `jobs get` output -- they do not exist:
- `duration`, `completed_at`, `objects`, `rows_read`, `total_rows`

## Summary

Present the result based on fields actually returned. Do NOT invent or assume field names. If `job_response` is absent, report the status and message only. If `object_details` is absent or empty, do not mention per-object breakdown.

Job statuses and their meanings:
- `pending` -- waiting for agent pickup
- `running` -- currently executing
- `completed` -- finished successfully
- `completed_with_warning` -- finished with non-fatal issues
- `failed` -- execution failed
- `cancelled` -- manually or automatically cancelled
