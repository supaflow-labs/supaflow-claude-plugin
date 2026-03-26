---
name: supaflow-quickstart
description: This skill should be used when the user asks to "set up a Supaflow pipeline from scratch", "end-to-end pipeline walkthrough", "getting started with Supaflow", "new pipeline setup", "connect source to destination", "set up data replication", "walk me through Supaflow", "build a pipeline", "Supaflow tutorial", "Supaflow quickstart", "I'm new to Supaflow", or mentions setting up a complete Supaflow data pipeline workflow for the first time. Provides the correct order of operations for going from zero to a running, scheduled pipeline.
---

# Supaflow End-to-End Pipeline Setup

Set up a complete data pipeline from authentication through scheduled syncs. This skill provides the correct order of operations -- individual command details are in the domain-specific skills (supaflow-auth, supaflow-datasources, supaflow-pipelines, supaflow-schedules, supaflow-jobs).

## Prerequisites

- Node.js 18+ installed
- `@getsupaflow/cli` installed: `npm install -g @getsupaflow/cli`
- A Supaflow account at `https://app.supa-flow.io`
- An API key created in Settings > API Keys (starts with `ak_`)
- Source and destination system credentials available

## Workflow Order

The eight steps below must be followed in order. Each step depends on the previous one.

### Step 1: Authenticate

```bash
supaflow auth login
# Paste API key when prompted

supaflow auth status --json
# Verify: authenticated = true
```

Or set environment variables for non-interactive use:

```bash
export SUPAFLOW_API_KEY=ak_xxx
export SUPAFLOW_WORKSPACE_ID=<uuid>
```

### Step 2: Select Workspace

```bash
supaflow workspaces list --json
supaflow workspaces select <name-or-api_name-or-uuid>
```

Pass the workspace name, api_name, or UUID directly to avoid interactive prompts. Skip if `SUPAFLOW_WORKSPACE_ID` is already set.

### Step 3: Create Source Datasource

```bash
# List available connector types
supaflow connectors list --json

# Scaffold env file for the source
supaflow datasources init --connector <TYPE> --name "<Source Name>" --json
# Example: supaflow datasources init --connector postgres --name "Production DB"

# Fill in connection details in the generated .env file
# Use ${VAR} references for secrets

# Create the datasource (tests connection first)
supaflow datasources create --from <source_name>.env --json
```

Wait for the connection test to succeed. On failure, fix credentials in the env file and retry.

### Step 4: Create Destination Datasource

Same process as Step 3 but for the destination warehouse:

```bash
supaflow datasources init --connector <TYPE> --name "<Destination Name>" --json
# Example: supaflow datasources init --connector snowflake --name "Data Warehouse"

# Fill in the env file
supaflow datasources create --from <destination_name>.env --json
```

Common destination types: `SNOWFLAKE`, `S3`.

### Step 5: Create a Project

A project ties pipelines to a destination warehouse:

```bash
supaflow projects create \
  --name "<Project Name>" \
  --destination <destination-api-name-or-uuid> \
  --json
```

### Step 6: Select Objects and Create Pipeline

Browse the source catalog and choose which objects (tables) to sync:

```bash
# Export discovered objects
supaflow datasources catalog <source-identifier> --output objects.json

# Edit objects.json: set "selected": false for objects to exclude

# Create the pipeline
supaflow pipelines create \
  --name "<Pipeline Name>" \
  --source <source-identifier> \
  --project <project-identifier> \
  --objects objects.json \
  --json
```

Optionally pass `--config pipeline-config.json` to override default settings (ingestion mode, load mode, etc.). If `--objects` is omitted, all discovered objects are selected.

### Step 7: Run the First Sync

```bash
supaflow pipelines sync <pipeline-identifier> --json
```

Monitor the resulting job:

```bash
supaflow jobs get <job-id> --json
```

Check per-object status and row counts. If the job fails, check logs:

```bash
supaflow jobs logs <job-id> --json
```

### Step 8: Schedule Recurring Syncs

```bash
supaflow schedules create \
  --name "<Schedule Name>" \
  --pipeline <pipeline-identifier> \
  --cron "<cron-expression>" \
  --timezone "<display-timezone>" \
  --json
```

Common cron patterns:
- Every hour: `"0 * * * *"`
- Every 6 hours: `"0 */6 * * *"`
- Daily at 2am UTC: `"0 2 * * *"`
- Weekdays at 9am UTC: `"0 9 * * 1-5"`

## Complete Example

```bash
# 1. Auth
supaflow auth login
supaflow workspaces select

# 2. Source
supaflow datasources init --connector postgres --name "Production DB" --json
# Edit production_db.env
supaflow datasources create --from production_db.env --json

# 3. Destination
supaflow datasources init --connector snowflake --name "Data Warehouse" --json
# Edit data_warehouse.env
supaflow datasources create --from data_warehouse.env --json

# 4. Project
supaflow projects create --name "Analytics" --destination data_warehouse --json

# 5. Object selection + Pipeline
supaflow datasources catalog production_db --output objects.json
# Edit objects.json
supaflow pipelines create \
  --name "Production to Warehouse" \
  --source production_db \
  --project analytics \
  --objects objects.json \
  --json

# 6. First sync
supaflow pipelines sync production_to_warehouse --json
# Monitor: supaflow jobs get <job-id> --json

# 7. Schedule
supaflow schedules create \
  --name "Hourly Sync" \
  --pipeline production_to_warehouse \
  --cron "0 * * * *" \
  --json
```

## Day-Two Operations

After the initial setup, common ongoing tasks:

| Task | Command | Skill |
|------|---------|-------|
| Check sync status | `supaflow jobs list --filter status=running --json` | supaflow-jobs |
| View failed jobs | `supaflow jobs list --filter status=failed --json` | supaflow-jobs |
| Update object selection | `supaflow pipelines schema select <id> --from objects.json --json` | supaflow-pipelines |
| Full resync | `supaflow pipelines sync <id> --full-resync --json` | supaflow-pipelines |
| Change schedule frequency | `supaflow schedules edit <name> --cron "new-cron" --json` | supaflow-schedules |
| Update credentials | `supaflow datasources edit <id> --from updated.env --json` | supaflow-datasources |
| Add new source tables | `supaflow datasources refresh <id> --json` then update schema | supaflow-datasources |
| Pause a pipeline | `supaflow pipelines disable <id> --json` | supaflow-pipelines |

## Decision Guide

When unsure which approach to take:

- **Ingestion mode**: Use `HISTORICAL_PLUS_INCREMENTAL` (default) unless there is a specific reason for `HISTORICAL` only or `INCREMENTAL` only
- **Load mode**: Use `MERGE` (default) for most cases; use `TRUNCATE_AND_LOAD` for lookup tables
- **Schema evolution**: Use `ALLOW_ALL` (default) for development; use `BLOCK_ALL` for production stability
- **Full resync frequency**: Use `NEVER` (default) unless data drift is a concern
- **Schedule frequency**: Hourly is a good starting point; adjust based on data freshness requirements
