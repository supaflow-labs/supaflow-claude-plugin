---
description: Trigger a sync and poll for completion
allowed-tools: Bash(supaflow *)
argument-hint: [pipeline-name]
---

# Sync a Supaflow Pipeline

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

## Step 1: Identify Pipeline

If a pipeline name was provided as an argument, find it in the list. If no argument was given, list all pipelines and ask the user which one to sync.

```bash
supaflow pipelines list --limit 200 --json | python3 -c "
import sys, json
d = json.load(sys.stdin)
if 'error' in d: print('ERROR: ' + d['error']['message']); sys.exit(1)
for p in d.get('data', []):
    src = p['source']
    dst = p['destination']
    print(f\"{p['name']} | {src['name']} ({src['connector_name']}) -> {dst['name']} ({dst['connector_name']}) | api_name={p['api_name']} | state={p['state']}\")
total = d.get('total', len(d.get('data', [])))
if total > len(d.get('data', [])):
    print(f'WARNING: showing {len(d[\"data\"])} of {total} pipelines. Use --offset to page.')
"
```

**Parser contract -- use these nested fields ONLY:**
- `p['source']['name']`, `p['source']['connector_name']`
- `p['destination']['name']`, `p['destination']['connector_name']`
- `p['api_name']`, `p['name']`, `p['state']`
- NEVER use flat fields like `source_name`, `destination_name`, or guessed names.

If a pipeline name was given, match by `name` or `api_name`. If no match is found, show the full list and ask the user to confirm which pipeline to sync. Capture the `api_name` for the sync command.

## Step 2: Trigger Sync

```bash
supaflow pipelines sync <PIPELINE_API_NAME> --json | python3 -c "
import sys,json; d=json.load(sys.stdin)
if 'error' in d: print('ERROR: ' + d['error']['message']); sys.exit(1)
print(f\"Job queued: id={d['job_id']} | pipeline={d['pipeline_id']} | status={d['status']}\")
"
```

**Parser contract -- pipelines sync response**

The sync response returns EXACTLY these 3 fields:
- `job_id` -- the job UUID to track
- `pipeline_id` -- the pipeline UUID
- `status` -- always "queued" on success

NEVER reference: `job_status`, `name`, `message`, or any other field from this response.

Capture `job_id` from the response for polling.

## Step 3: Poll for Completion

Ask the user: "Want me to poll for completion?"

If yes, poll using `jobs status` with 30-second intervals (default). Use a different interval only if the user explicitly asks.

**`jobs status` is ONLY for polling.** It tells you whether the job is still running. It does NOT provide final results. You MUST run `jobs get` after polling reaches a terminal state (Step 4).

```bash
job_id="<JOB_ID>"
for poll_i in $(seq 1 60); do
  poll_result=$(supaflow jobs status "$job_id" --json 2>&1)
  job_status=$(echo "$poll_result" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('job_status','unknown'))" 2>/dev/null || echo "error")
  poll_msg=$(echo "$poll_result" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('status_message',''))" 2>/dev/null || echo "")
  echo "[$poll_i] job_status=$job_status message=$poll_msg"
  if [ "$job_status" = "completed" ] || [ "$job_status" = "completed_with_warning" ] || [ "$job_status" = "failed" ] || [ "$job_status" = "cancelled" ] || [ "$job_status" = "timed_out" ]; then
    break
  fi
  sleep 30
done
echo "Final status: $job_status"
```

**IMPORTANT shell variable rules:**
- Use `job_status` NOT `status` (read-only in zsh)
- Use `poll_i` NOT `i` (avoid collisions)
- Use `poll_result` NOT `result` (clarity)
- Use `poll_msg` NOT `msg` (clarity)

**Parser contract -- jobs status**

Parse ONLY: `id`, `job_status`, `status_message`, `job_response`
NEVER use: `phase`, `duration`, `completed_at`, `progress`

## Step 4: Final Results (MANDATORY)

**HARD GATE: When polling reaches a terminal state, you MUST run `jobs get` before responding to the user.** Do not end on `jobs status` alone. `jobs status` is only for polling -- it does not contain per-object details or row counts.

```bash
supaflow jobs get <JOB_ID> --json | python3 -c "
import sys,json; d=json.load(sys.stdin)
if 'error' in d: print(d['error']['message']); sys.exit(1)
dur = d.get('execution_duration_ms', 0)
resp = d.get('job_response') or {}
print(f\"Status: {d['job_status']} | Duration: {dur/1000:.1f}s\")
print(f\"Objects: {resp.get('total_objects', '?')} | Rows: {resp.get('total_rows_source', '?')} source, {resp.get('total_rows_destination', '?')} dest | Failed: {resp.get('total_failed', 0)} | Skipped: {resp.get('total_skipped', 0)}\")
print()
for o in d.get('object_details', []):
    name = o['fully_qualified_source_object_name']
    rows = (o.get('ingestion_metrics') or {}).get('output_row_count', 0)
    print(f\"  {name}: ingestion={o['ingestion_status']} staging={o['staging_status']} loading={o['loading_status']} ({rows} rows)\")
"
```

**Required final summary format** -- present ALL of these to the user:
- Final job status
- Duration
- Total objects
- Total rows source / destination
- Failed / skipped counts
- Per-object list with stage statuses and row counts

**Parser contract -- jobs get**

Use ONLY: `execution_duration_ms`, `ended_at`, `job_response`, `object_details`
NEVER use: `duration`, `completed_at`, `objects`, `rows_read`

`job_response` fields: `total_objects`, `total_rows_source`, `total_rows_destination`, `total_failed`, `total_skipped`

For each entry in `object_details`:
- Object name: `fully_qualified_source_object_name`
- Stage statuses: `ingestion_status`, `staging_status`, `loading_status`
- Row count: `ingestion_metrics.output_row_count`
- Per-stage metrics: `ingestion_metrics`, `staging_metrics`, `loading_metrics`

## On Failure

If `job_status` is `failed`:
- Show the error from `status_message` and `job_response`
- Suggest: "Use `/explain-job-failure <job-id>` for detailed diagnosis including logs."
- Do NOT blindly retry.

## Full Resync Option

If the user mentions "full resync", "reset", or "re-sync from scratch":

```bash
supaflow pipelines sync <PIPELINE_API_NAME> --full-resync --json
```

If the user also asks to reset destination tables:

```bash
supaflow pipelines sync <PIPELINE_API_NAME> --full-resync --reset-target --json
```

Warn the user: "This will reset all cursors and re-sync from scratch. `--reset-target` will also drop and recreate destination tables. Confirm?" Wait for explicit yes before running either command.
