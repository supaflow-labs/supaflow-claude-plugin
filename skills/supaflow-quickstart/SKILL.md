---
name: supaflow-quickstart
description: This skill should be used when the user asks to "set up a Supaflow pipeline from scratch", "end-to-end pipeline walkthrough", "getting started with Supaflow", "new pipeline setup", "connect source to destination", "set up data replication", "walk me through Supaflow", "build a pipeline", "Supaflow tutorial", "Supaflow quickstart", "I'm new to Supaflow", or mentions setting up a complete Supaflow data pipeline workflow for the first time. Provides the correct order of operations for going from zero to a running, scheduled pipeline.
---

# Supaflow End-to-End Pipeline Setup

**AGENT BEHAVIOR:**
- **Execute commands directly via Bash.** Do NOT ask the user to run commands manually.
- **Preserve context window.** Pipe `--json` output through `python3 -c` to extract only the fields you need. NEVER dump full JSON into the conversation. For large outputs (catalog, schema list, jobs), write to a file and parse with a script.
- **Use `jobs status` for polling** (4 fields, ~100 bytes). Only use `jobs get` after the job reaches a terminal state.
- **NEVER ask for all credentials upfront.** Work step by step: authenticate first, then list existing datasources before asking for anything. The user likely already has datasources configured.
- **Follow the numbered steps below IN ORDER.** Do not skip ahead, do not batch questions. Complete each step before moving to the next. Each step tells you exactly what to ask and when.

Set up a complete data pipeline from authentication through scheduled syncs. This skill provides the correct order of operations -- individual command details are in the domain-specific skills (supaflow-auth, supaflow-datasources, supaflow-pipelines, supaflow-schedules, supaflow-jobs).

## Prerequisites

Before starting, verify:
1. CLI installed: run `supaflow --version`. If not found, run `npm install -g @getsupaflow/cli`

Do NOT ask for API keys, credentials, or connection details yet. The steps below tell you exactly when to ask for each piece of information.

## Step 0: Read Connector Documentation

**Before building anything, understand what you're building.** Read the relevant connector docs for the source and destination the user mentioned. The docs explain prerequisites, configuration properties, sync modes, and troubleshooting.

```bash
# Save source connector docs to a file (do NOT dump full docs into context)
supaflow docs <source-type> --output /tmp/source-docs.txt
# Read only the sections you need (prerequisites, configuration, query modes)

# Save destination connector docs
supaflow docs <destination-type> --output /tmp/dest-docs.txt

# Save pipeline configuration docs
supaflow docs pipelines --output /tmp/pipeline-docs.txt
```

The `docs` command fetches and caches documentation locally (24h TTL), then returns only the relevant section. **Always use `--output` to save to a file, then read only the subsections you need.** Connector docs can be 400+ lines -- do not dump the entire output into the conversation.

**Examples for a SQL Server to Snowflake pipeline:**
```bash
supaflow docs sqlserver --output /tmp/sqlserver-docs.txt
# Then read prerequisites and CT configuration sections from the file

supaflow docs snowflake --output /tmp/snowflake-docs.txt
# Then read auth methods and setup sections from the file
```

Use `supaflow docs --list` to see all available topics. Aliases are supported: `sql_server`, `postgres`, `sfmc`, `otm`, `iceberg`, etc.

After reading the docs, you'll know:
- What prerequisites the user needs (DB users, permissions, firewall rules)
- What connector properties matter for their use case (e.g., `queryMode: CHANGE_TRACKING`)
- What pipeline settings to recommend

Then proceed with the workflow steps below.

## Workflow Order

The steps below must be followed in order. Each step depends on the previous one.

### Step 1: Check Auth Status

**Run `auth status` FIRST** -- the user may already be authenticated from a previous session:

```bash
supaflow auth status --json
```

- If `authenticated: true` AND `workspace_id` is set: skip to Step 3.
- If `authenticated: true` but no workspace: skip to Step 2.
- If `authenticated: false`: ask the user for their API key (from Settings > API Keys at `https://app.supa-flow.io`), then:

```bash
supaflow auth login --key <api-key>
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

### Step 3: Check Existing Datasources

**MANDATORY: Run this BEFORE asking the user for any credentials.** The user likely already has datasources configured.

```bash
supaflow datasources list --json | python3 -c "
import sys,json; d=json.load(sys.stdin)
if 'error' in d: print(d['error']['message']); sys.exit(1)
for ds in d['data']:
    print(f\"{ds['name']} | {ds['connector_type']} | api_name={ds['api_name']} | state={ds['state']}\")
"
```

**Important:** List commands return `{ "data": [...] }` -- always access `['data']` to get the array.

Review the list and tell the user what you found. For example:
- "You have a SQL Server source called 'SQL Server' and a Snowflake destination called 'Snowflake'. We can use those. Do you want to use the existing ones or create new connections?"
- "You have a Snowflake destination but no SQL Server source. I'll need to set up the source."
- "No existing datasources. I'll set up both source and destination."

**Only proceed to create datasources that are actually missing.** If both exist, skip to Step 3b.

### Step 3b: Inspect Datasource Configuration (when reusing existing)

**If the user mentioned connector-specific features** (Change Tracking, CDC, Iceberg, Parquet, Glue, auth method, etc.), you MUST verify the existing datasource has those features enabled. These are connector properties, NOT pipeline settings.

```bash
supaflow datasources get <api_name> --json | python3 -c "
import sys,json; d=json.load(sys.stdin)
if 'error' in d: print(d['error']['message']); sys.exit(1)
c = d.get('configs', {})
for k,v in sorted(c.items()):
    if isinstance(v, dict): print(f'{k}: [encrypted]')
    elif v is not None and v != '': print(f'{k}: {v}')
"
```

Check the relevant config property for the user's request:

| User asks for | Check this config property | Connector |
|---------------|---------------------------|-----------|
| Change Tracking / CT | `queryMode` = `CHANGE_TRACKING` | SQL Server |
| CDC / logical replication | replication slot / publication | PostgreSQL |
| Iceberg / Parquet format | `outputFormat` | S3 / S3 Data Lake |
| Glue catalog | Glue-related properties | S3 |

**If the feature is not enabled:** Tell the user and offer to either edit the existing datasource (`datasources get <id> --output current.env`, modify, then `datasources edit`) or create a new one with the feature enabled.

**If the feature is enabled:** Confirm to the user and proceed to Step 5.

**If multiple datasources of the same type exist:** Inspect each one to find which has the feature enabled, or ask the user which to use.

### Step 4: Create Missing Datasources (if needed)

Only for datasources that don't already exist from Step 3. For each one:

```bash
# Scaffold env file
supaflow datasources init --connector <TYPE> --name "<Name>" --json
# Example: supaflow datasources init --connector sqlserver --name "SQL Server"
# Example: supaflow datasources init --connector snowflake --name "Data Warehouse"
```

Then follow the supaflow-datasources skill for filling credentials (ask for credential files first, only ask non-sensitive fields in chat, never ask for passwords directly).

```bash
# Create (tests connection first)
supaflow datasources create --from <name>.env --json
```

Wait for the connection test to succeed. On failure, fix credentials in the env file and retry.

### Step 5: Find or Create a Project

A project ties pipelines to a destination warehouse. **Check if one already exists for the destination first:**

```bash
supaflow projects list --json | python3 -c "
import sys,json; d=json.load(sys.stdin)
if 'error' in d: print(d['error']['message']); sys.exit(1)
for p in d['data']:
    print(f\"{p['name']} | warehouse_id={p.get('warehouse_datasource_id','?')} | dest={p.get('warehouse_name','?')} | pipelines={p.get('pipeline_count',0)} | api_name={p['api_name']}\")
"
```

**Match by `warehouse_datasource_id`** (not `warehouse_name`). Compare against the destination datasource's `id` from Step 3. If a project matches, use its `api_name`. Only create a new project if none matches:

```bash
supaflow projects create \
  --name "<Project Name>" \
  --destination <destination-api-name-or-uuid> \
  --json
```

### Step 6: Select Objects and Create Pipeline

First, check if a pipeline already exists between this source and destination:

```bash
supaflow pipelines list --json
```

If a matching pipeline exists, ask the user if they want to edit it or add objects to it instead. Creating duplicate pipelines to the same destination causes merge conflicts and data corruption.

If the user still wants a separate pipeline, you MUST ask them to explicitly confirm that they want a separate destination schema prefix before creating it.

If creating a new pipeline, follow these sub-steps in order:

**6a. Ask for pipeline name.** Suggest a default (e.g., `sql_server_to_snowflake`) but let the user override.

**6b. Browse source catalog and select objects.**

```bash
supaflow datasources catalog <source-identifier> --output /tmp/objects.json
# Parse and present available objects
```

Ask the user which objects to include. Edit `/tmp/objects.json` to set `"selected": false` for excluded objects. Each entry must have `fully_qualified_name`, `selected`, and `fields` (null = all fields).

**6c. ALWAYS run `pipelines init` to generate config.** This is mandatory, not optional.

```bash
supaflow pipelines init --source <source> --project <project> --output /tmp/pipeline-config.json --json
```

**6d. Read and present the ACTUAL config values from the generated file.** Show:
- Pipeline prefix (CANNOT be changed after creation)
- Ingestion mode
- Load mode
- Schema evolution
- Hard deletes

NEVER manually derive defaults from capabilities. NEVER say "auto-generated prefix" without showing the actual value from the file.

**6e. Wait for explicit user confirmation.** This is a hard gate. If the user requests changes, edit the config file, re-read it, show ALL final values, and ask again. NEVER treat a partial edit as blanket approval.

**6f. Create the pipeline.**

```bash
supaflow pipelines create \
  --name "<Pipeline Name>" \
  --source <source-identifier> \
  --project <project-identifier> \
  --config /tmp/pipeline-config.json \
  --objects /tmp/objects.json \
  --json
```

If create fails with a duplicate constraint: STOP, show the error, ask what to do. NEVER silently rename or auto-increment.

### Step 7: Run the First Sync

Before syncing a newly created pipeline, verify the selected objects with `pipelines schema list`. Do NOT trust summary fields from `pipelines create` alone.

```bash
supaflow pipelines schema list <pipeline-identifier> --json
```

Compare the selected objects against the intended `objects.json`. If they don't match, stop and fix the pipeline selection before starting the first sync.

```bash
supaflow pipelines sync <pipeline-identifier> --json
```

The sync returns `{ "job_id": "...", "pipeline_id": "...", "status": "queued" }`. Poll the job with lightweight status:

```bash
supaflow jobs status <job-id> --json
# Repeat until job_status is completed, failed, or cancelled
```

Once terminal, get full per-object details:

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
# 1. Auth (non-interactive -- pass key and workspace name directly)
supaflow auth login --key <api-key>
supaflow workspaces select Dev

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
# Poll: supaflow jobs status <job-id> --json
# Details: supaflow jobs get <job-id> --json

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
