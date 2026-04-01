---
description: Diagnose a failed job
allowed-tools: Bash(supaflow *)
argument-hint: [job-id]
---

# Explain Supaflow Job Failure

Diagnose why a specific job failed by retrieving job details and reading the execution logs.

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

## Step 1: Get Job Details

Retrieve the full job record to identify which objects and stages failed.

```bash
supaflow jobs get <JOB_ID> --json | python3 -c "
import sys, json
j = json.load(sys.stdin)
if 'error' in j: print('ERROR: ' + j['error']['message']); sys.exit(1)
dur = j.get('execution_duration_ms', 0)
print(f\"Status: {j['job_status']} | Duration: {dur}ms | Message: {j.get('status_message', '')}\")
resp = j.get('job_response') or {}
print(f\"Objects: {resp.get('total_objects', 0)} | Failed: {resp.get('total_failed', 0)} | Skipped: {resp.get('total_skipped', 0)}\")
print()
print('Failed objects:')
failed = [o for o in j.get('object_details', []) if o.get('ingestion_status') == 'failed' or o.get('staging_status') == 'failed' or o.get('loading_status') == 'failed']
if not failed:
    print('  (no per-object failures found -- check logs for top-level error)')
for o in failed:
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
- `job_response` -- summary object with `total_objects`, `total_rows_source`, `total_rows_destination`, `total_failed`, `total_skipped`
- `object_details` -- array of per-object stage records

For each entry in `object_details`:
- Object name: `fully_qualified_source_object_name`
- Stage statuses: `ingestion_status`, `staging_status`, `loading_status`
- Row count: `ingestion_metrics.output_row_count`

NEVER reference these fields from `jobs get` output -- they do not exist:
- `duration`, `completed_at`, `objects`, `rows_read`, `error`, `stack_trace`

## Step 2: Read Job Logs

Download the full job log to a temp file, then search for error lines. The log contains the authoritative root cause.

```bash
supaflow jobs logs <JOB_ID> > /tmp/supaflow-job-logs.txt
```

After the log is written, search for error and exception lines:

```bash
supaflow jobs logs <JOB_ID> > /tmp/supaflow-job-logs.txt && python3 -c "
import re, sys
errors = []
with open('/tmp/supaflow-job-logs.txt') as f:
    for line in f:
        if re.search(r'ERROR|FATAL|Exception|WARN', line):
            errors.append(line.rstrip())
if not errors:
    print('No ERROR/FATAL/Exception/WARN lines found in logs.')
else:
    for e in errors[:50]:
        print(e)
    if len(errors) > 50:
        print(f'... and {len(errors) - 50} more error lines.')
"
```

Read the relevant error lines carefully. Do NOT dump the entire log file into the conversation -- extract only the lines that explain the failure.

## Step 3: Diagnose and Report

Based on the job details from Step 1 and the log errors from Step 2, present a clear diagnosis:

1. **What failed** -- which object(s) and which pipeline stage (ingestion, staging, or loading).
2. **Root cause** -- the actual error message from the logs. Quote the log line directly.
3. **Recommended fix** -- a concrete action the user can take.

NEVER blindly retry a failed job without understanding the cause. NEVER guess field names or make up error details not present in the actual output. Base the summary only on fields actually returned by the commands.

Common failure causes and their fixes:

| Log pattern | Likely cause | Fix |
|-------------|-------------|-----|
| `Connection refused` / `Unable to connect` | Source or destination unreachable | Verify network connectivity and datasource credentials |
| `Authentication failed` / `Invalid credentials` | Expired or rotated credentials | Update the datasource credentials via `supaflow datasources edit` |
| `permission denied` / `insufficient privilege` | Missing database permissions | Grant required privileges on the source or destination |
| `rate limit` / `429` / `Too Many Requests` | Source API throttled | Reduce sync frequency or contact source provider |
| `schema` / `column` / `type mismatch` | Schema evolution conflict | Run `supaflow pipelines sync <name> --full-resync --reset-target --json` |
| `timeout` / `deadline exceeded` | Ingestion took too long | Reduce object selection or increase pipeline timeout configuration |
| `No space left` / `disk full` | Destination storage exhausted | Free space or expand destination capacity |

## Step 4: Offer Fix (If Actionable)

If the diagnosis leads to a clear corrective action, offer to run it. Examples:

- If credentials are stale: `supaflow datasources test <datasource-id> --json` to verify after user updates credentials.
- If schema conflict: `supaflow pipelines sync <pipeline-name> --full-resync --reset-target --json`
- If the issue was transient (network blip, temporary rate limit): `supaflow pipelines sync <pipeline-name> --json`

Do NOT offer to retry until you have identified and communicated the root cause. If the cause is unclear from the logs, say so explicitly and suggest the user check the datasource connectivity directly.
