---
name: supaflow-jobs
description: Use when you need reference information about Supaflow job lifecycle, per-object metrics, log analysis, job statuses, or execution details
---

# Supaflow Job Monitoring

**This is a reference skill, not a workflow.** For job inspection, use `/check-job` or `/explain-job-failure` commands. This skill provides background knowledge about job lifecycle, per-object metrics, and log analysis.

Jobs are async execution records created by pipeline syncs, datasource tests, and schema refreshes. Every `pipelines sync`, `datasources create`, `datasources test`, and `datasources refresh` command creates a job.

All CLI commands require authentication and an active workspace.

## Listing Jobs

```bash
# List recent jobs
supaflow jobs list --json

# Filter by status
supaflow jobs list --filter status=running --json
supaflow jobs list --filter status=failed --json
supaflow jobs list --filter status=completed --json
supaflow jobs list --filter status=pending --json

# Filter by pipeline
supaflow jobs list --filter pipeline=<pipeline-uuid> --json
```

List output follows the standard contract:

```json
{
  "data": [
    {
      "id": "13cfe303-c67e-...",
      "job_type": "pipeline_run",
      "job_status": "completed",
      "reference_id": "3d72f887-...",
      "reference_type": "pipeline",
      "created_at": "2026-03-25T10:00:00Z",
      "updated_at": "2026-03-25T10:01:00Z"
    }
  ],
  "total": 5,
  "limit": 25,
  "offset": 0
}
```

Available filters: `status` (by job_status), `pipeline` (by pipeline UUID), `type` (by job_type). Supports `--limit <n>` (default 25) and `--offset <n>` for pagination.

## Viewing Job Details

```bash
supaflow jobs get <job-id> --json
```

**`jobs get` is context-aware:** while a job is running, it may return only lightweight status. Once the job reaches a terminal state (completed, failed, etc.), it includes full per-object details with metrics. Even so, prefer `jobs status` for polling and use `jobs get` only after terminal state.

**Polling pattern for agents:**
```bash
# Use `jobs status` for polling -- 4 fields, lightweight while job is running
supaflow jobs status <job-id> --json
# While running: { "id": "...", "job_status": "running", "status_message": "...", "job_response": null }
# After terminal: { "id": "...", "job_status": "completed", "status_message": "...", "job_response": { "total_objects": 2, ... } }

# Once terminal (completed/failed), use `jobs get` for per-object breakdown
supaflow jobs get <job-id> --json
# Returns: job header + object_details with per-object metrics
```

**IMPORTANT: In polling loops, NEVER use `status` as a shell variable name.** It is a read-only builtin in zsh. Use `job_status` or `poll_status` instead.

**Use `jobs status` (not `jobs get`) for polling.** While a job is running, `job_response` is null and the payload is ~100 bytes. After terminal state, `job_response` includes summary counts (total_objects, total_rows_source, total_rows_destination, total_failed, total_skipped). Use `jobs get` only when you need per-object stage metrics.

Job details (only in terminal state) include per-object metrics showing the three-stage pipeline execution:

- **Ingestion**: Read records from source
- **Staging**: Write records to temporary storage
- **Loading**: Merge records into destination

Human-readable output format:

```
Job:      13cfe303-c67e-...
Type:     pipeline_run
Status:   completed
Duration: 58s

Object Details:
OBJECT                    INGESTION   STAGING     LOADING     ROWS
public.accounts           completed   completed   completed   14
public.contacts           completed   completed   completed   16
public.tasks              completed   completed   completed   3
```

**`jobs get` JSON field names** -- use EXACTLY these names, do NOT guess alternatives:

```bash
supaflow jobs get <job-id> --json | python3 -c "
import sys,json; j=json.load(sys.stdin)
if 'error' in j: print(j['error']['message']); sys.exit(1)
dur = j.get('execution_duration_ms', 0)
print(f\"Status: {j['job_status']} | Duration: {dur}ms | Message: {j.get('status_message','')}\")
resp = j.get('job_response') or {}
print(f\"Objects: {resp.get('total_objects',0)} | Rows: {resp.get('total_rows_source',0)} source, {resp.get('total_rows_destination',0)} dest | Failed: {resp.get('total_failed',0)}\")
for o in j.get('object_details', []):
    name = o['fully_qualified_source_object_name']
    rows = (o.get('ingestion_metrics') or {}).get('output_row_count', 0)
    print(f\"  {name}: ingestion={o['ingestion_status']} staging={o['staging_status']} loading={o['loading_status']} ({rows} rows)\")
"
```

**Field name cheat sheet (do NOT invent alternatives):**
- Job header: `job_status`, `status_message`, `execution_duration_ms`, `job_type`, `reference_id`, `reference_type`, `job_response`
- Job response: `total_objects`, `total_rows_source`, `total_rows_destination`, `total_failed`, `total_skipped`
- Object details array: `object_details` (NOT `objects` or `object_statuses`)
- Object name: `fully_qualified_source_object_name` (NOT `object_name` or `name`)
- Object stages: `ingestion_status`, `staging_status`, `loading_status` (NOT `status` or `object_status`)
- Object metrics: `ingestion_metrics.output_row_count` (NOT `rows_extracted` or `rows_read`)

**`jobs logs` uses DIFFERENT field names** (not `job_status`/`status_message`/`job_response`):
```json
{ "id": "...", "status": "completed", "message": null, "response": { ... } }
```

## Job Logs

View the job response and log output:

```bash
supaflow jobs logs <job-id> --json
```

Logs contain detailed information about errors, warnings, and execution progress. Check logs first when diagnosing failures.

## Job Statuses

| Status | Meaning |
|--------|---------|
| `pending` | Job created, waiting for agent pickup |
| `running` | Currently executing |
| `completed` | Finished successfully |
| `completed_with_warning` | Finished but with non-fatal issues |
| `failed` | Execution failed |
| `cancelled` | Manually or automatically cancelled |

## Job Types

| Type | Created by |
|------|-----------|
| `pipeline_run` | `pipelines sync` |
| `datasource_test` | `datasources create`, `datasources test` |
| `datasource_schema_refresh` | `datasources refresh`, `datasources catalog --refresh` |

## Diagnosing Failures

When a job fails, follow this sequence:

1. **Get job details** to see which object and stage failed:
   ```bash
   supaflow jobs get <job-id> --json
   ```

2. **Check logs** for error messages:
   ```bash
   supaflow jobs logs <job-id> --json
   ```

3. **Common failure causes**:
   - Connection failures: Datasource credentials changed or network issues
   - Schema changes: Source schema evolved and destination cannot accommodate
   - Permission errors: Insufficient privileges on source or destination
   - Rate limiting: Source API throttled requests
   - Timeout: Long-running ingestion exceeded time limits

4. **After fixing the root cause**, re-run the pipeline:
   ```bash
   supaflow pipelines sync <identifier> --json
   ```

   For persistent schema issues, use full resync with target reset:
   ```bash
   supaflow pipelines sync <identifier> --full-resync --reset-target --json
   ```

## Common Operations

### Trigger sync and poll for completion

```bash
# Start the sync
supaflow pipelines sync my_pipeline --json
# Returns: { "job_id": "...", "pipeline_id": "...", "status": "queued" }

# Poll with lightweight status
supaflow jobs status <job-id> --json
# Repeat until job_status is completed, failed, or cancelled

# Get full details after terminal state
supaflow jobs get <job-id> --json
```

### Find failed jobs in the last batch

```bash
supaflow jobs list --filter status=failed --json
```

### Get row counts from a completed job

```bash
supaflow jobs get <job-id> --json
# Parse per-object row counts from the response
```

### Check if any jobs are currently running

```bash
supaflow jobs list --filter status=running --json
# Check if data array is non-empty
```

## Identifier Resolution

Job commands use the job UUID (returned by sync, create, test, and refresh commands):

```bash
supaflow jobs get 13cfe303-c67e-4a5b-8f9d-1e2f3a4b5c6d --json
supaflow jobs logs 13cfe303-c67e-4a5b-8f9d-1e2f3a4b5c6d --json
```
