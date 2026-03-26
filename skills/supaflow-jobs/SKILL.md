---
name: supaflow-jobs
description: This skill should be used when the user asks to "check job status", "monitor a pipeline run", "view job logs", "list running jobs", "check failed jobs", "get job details", "see job metrics", "troubleshoot a failed sync", "view job errors", "why did my pipeline fail", "debug pipeline failure", or mentions Supaflow jobs, pipeline execution status, sync progress, or job monitoring. Covers job listing, status inspection, and log retrieval in the @getsupaflow/cli.
---

# Supaflow Job Monitoring

Jobs are async execution records created by pipeline syncs, datasource tests, and schema refreshes. Every `pipelines sync`, `datasources create`, `datasources test`, and `datasources refresh` command creates a job.

All commands require prior authentication and workspace selection (see the supaflow-auth skill).

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
      "type": "pipeline_run",
      "status": "completed",
      "duration": "58s",
      "created_at": "2026-03-25T10:00:00Z"
    }
  ],
  "total": 5,
  "limit": 25,
  "offset": 0
}
```

## Viewing Job Details

```bash
supaflow jobs get <job-id> --json
```

Job details include per-object metrics showing the three-stage pipeline execution:

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

With `--json`, the response includes structured per-object detail with status, row counts, and timing for each stage.

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
| `connection_test` | `datasources create`, `datasources test` |
| `schema_refresh` | `datasources refresh`, `datasources catalog --refresh` |

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

## Common Agent Patterns

### Trigger sync and poll for completion

```bash
# Start the sync
supaflow pipelines sync my_pipeline --json
# Extract job ID from output

# Check status
supaflow jobs get <job-id> --json
# Repeat until status is completed, failed, or cancelled
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
