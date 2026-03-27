---
name: supaflow-pipelines
description: This skill should be used when the user asks to "create a pipeline", "sync data", "run a pipeline", "full resync", "reset target", "edit pipeline config", "select objects", "manage schema", "set ingestion mode", "configure load mode", "pipeline settings", "disable pipeline", "enable pipeline", "delete pipeline", "list pipelines", or mentions Supaflow pipelines, data replication, object selection, or pipeline configuration. Covers the full pipeline lifecycle including schema management in the @getsupaflow/cli.
---

# Supaflow Pipeline Management

**AGENT BEHAVIOR:**
- **Execute all CLI commands directly via Bash.** Do NOT ask the user to run commands manually.
- **Preserve context window.** Pipe `--json` output through `python3 -c` to extract only the fields you need. NEVER dump full JSON into the conversation. For schema list and object selection, parse with scripts.
- **Only ask the user for:** pipeline name, object selection preferences, and config choices.

Pipelines move data from a source datasource to a destination warehouse. Each pipeline belongs to a project (which defines the destination) and selects which objects to sync.

All commands require prior authentication and workspace selection (see the supaflow-auth skill).

## Projects

Pipelines belong to projects. A project ties pipelines to a destination warehouse datasource.

```bash
# List projects
supaflow projects list --json

# Create a project
supaflow projects create --name "My Project" --destination <datasource-identifier> --json
```

The `--destination` flag accepts a datasource UUID or api_name. Optional: `--type <type>` (values: `pipeline`, `ingestion`, `transformation`, `activation`; default: `pipeline`).

**Only two project commands exist:** `list` and `create`. There is no `projects get`. Use `projects list` to find existing projects -- it returns `warehouse_datasource_id`, `warehouse_name`, `warehouse_connector_name`, and `pipeline_count`.

**Before creating a project, check if one already exists for the destination:**
```bash
supaflow projects list --json | python3 -c "
import sys,json; d=json.load(sys.stdin)
if 'error' in d: print(d['error']['message']); sys.exit(1)
for p in d['data']:
    print(f\"{p['name']} | warehouse_id={p.get('warehouse_datasource_id','?')} | dest={p.get('warehouse_name','?')} ({p.get('warehouse_connector_name','?')}) | pipelines={p.get('pipeline_count',0)} | api_name={p['api_name']}\")
"
```

**Match projects by `warehouse_datasource_id`** (not `warehouse_name` which is a display label and may not be unique). Compare against the destination datasource's `id` from `datasources list`. If a project already exists for that destination ID, use it. Only create a new project if none matches.

## Before Creating a Pipeline

**Always check for existing pipelines between the same source and destination first.** Duplicate pipelines writing to the same destination schema cause merge conflicts and data corruption.

```bash
supaflow pipelines list --json | python3 -c "
import sys,json; d=json.load(sys.stdin)
if 'error' in d: print(d['error']['message']); sys.exit(1)
for p in d['data']:
    print(f\"{p['name']} | {p['source']['connector_name']} -> {p['destination']['connector_name']} | api_name={p['api_name']} | state={p['state']}\")
"
```

**Important:** List commands return `{ "data": [...] }` -- always access `['data']` to get the array.

Review the results for pipelines with the same source and destination. If one exists, inform the user:
- What pipeline already exists (name, source, destination)
- What objects it syncs (`supaflow pipelines schema list <identifier> --json`)
- Offer to **edit** the existing pipeline or **add objects** to it instead of creating a new one
- If the user still wants a new pipeline, warn that it should use different objects or a different destination schema prefix to avoid writing to the same tables

Only create a new pipeline if no existing pipeline covers the same source-destination pair, or the user explicitly confirms they want a separate one.

## Creating a Pipeline

**MANDATORY: Before running `pipelines create`, read source and destination capabilities, then present only valid options to the user.** Do NOT silently use defaults. Do NOT show options the connectors don't support.

### Reading Connector Capabilities

`datasources get` returns a `capabilities` object on each datasource. Use it to determine which pipeline options are valid:

```bash
# Get source capabilities (controls ingestion_mode)
supaflow datasources get <source> --json | python3 -c "
import sys,json; d=json.load(sys.stdin)
caps = d.get('capabilities', {})
for k in ['ingestion_mode','perform_hard_deletes','checksum_validation_level']:
    v = caps.get(k)
    if v: print(f'{k}: supported={v.get(\"supported_values\",v.get(\"supported\"))}, default={v.get(\"default_value\")}')
"

# Get destination capabilities (controls load_mode, schema_evolution_mode, namespace_rules, etc.)
supaflow datasources get <destination> --json | python3 -c "
import sys,json; d=json.load(sys.stdin)
caps = d.get('capabilities', {})
for k in ['load_mode','schema_evolution_mode','namespace_rules','destination_table_handling','load_optimization_mode','perform_hard_deletes']:
    v = caps.get(k)
    if v: print(f'{k}: supported={v.get(\"supported_values\",v.get(\"supported\"))}, default={v.get(\"default_value\")}')
"
```

### Capability Ownership Rules

Each setting is controlled by either the source, destination, or both:

| Setting | Controlled By | Resolution |
|---------|--------------|------------|
| `ingestion_mode` | **source** | Only show values from source capabilities |
| `load_mode` | **destination** | Only show values from destination capabilities |
| `schema_evolution_mode` | **destination** | Only show values from destination capabilities |
| `namespace_rules` | **destination** | Only show values from destination capabilities |
| `destination_table_handling` | **destination** | Only show values from destination capabilities |
| `load_optimization_mode` | **destination** | Only show values from destination capabilities |
| `checksum_validation_level` | **both** | Intersection of source + destination values |
| `perform_hard_deletes` | **both** | Only if BOTH source AND destination support it |

For "both" settings: `enabled` requires AND of both connectors, `supported_values` uses intersection. Only highlight a default if it appears in the intersection -- if it doesn't, present the intersection without a pre-selected default and ask the user to choose.

### Presenting Options to the User

After reading capabilities, present a summary showing only valid options with defaults highlighted. Example:

```
Pipeline configuration (defaults shown, change any you want):
- Destination schema prefix: sqlserver (auto-generated, CANNOT be changed later)
- Ingestion mode: HISTORICAL_PLUS_INCREMENTAL [INCREMENTAL, HISTORICAL also available]
- Load mode: MERGE [APPEND, TRUNCATE_AND_LOAD, OVERWRITE also available]
- Schema evolution: ALLOW_ALL [BLOCK_ALL, COLUMN_LEVEL_ONLY also available]

Reply with any changes, or "defaults are fine" to proceed.
```

**Important:** The destination schema prefix CANNOT be changed after pipeline creation. Always highlight this.

If the user says "just use defaults" or similar, skip the config file. Otherwise, create a config JSON with their overrides.

**Pipeline prefix** (destination schema name):
- Auto-generated from source type (e.g., `sqlserver`, `hubspot`)
- Ask: "Your data will be written to the `<source_type>` schema in the destination. Want to use this or a custom prefix?"
- If custom, set `pipeline_prefix` and `is_custom_prefix: true` in config

If the user wants non-default settings, create a config file:
```bash
echo '{"ingestion_mode": "INCREMENTAL", "load_mode": "APPEND", "pipeline_prefix": "my_custom_schema", "is_custom_prefix": true}' > pipeline-config.json
supaflow pipelines create ... --config pipeline-config.json --json
```

```bash
# Minimal: all discovered objects selected, default config
supaflow pipelines create \
  --name "Postgres to Snowflake" \
  --source <datasource-identifier> \
  --project <project-identifier> \
  --json

# With specific object selection
supaflow pipelines create \
  --name "Postgres to Snowflake" \
  --source my_postgres \
  --project my_project \
  --objects objects.json \
  --json

# With custom pipeline config
supaflow pipelines create \
  --name "Postgres to Snowflake" \
  --source my_postgres \
  --project my_project \
  --objects objects.json \
  --config pipeline-config.json \
  --json
```

The `--source` and `--project` flags accept UUID or api_name. The destination is resolved from the project. Optional: `--description <desc>` adds a human-readable description.

### Destination Schema (Pipeline Prefix)

By default, Supaflow auto-generates a destination schema name based on the source connector type (e.g., `salesforce`, `postgres`, `hubspot`). If a pipeline with that source type already exists, it appends a number (`salesforce_2`, `salesforce_3`, etc.).

Before creating, inform the user:
- "This pipeline will write to the `<source_type>` schema in your destination. If that schema doesn't exist, it will be created automatically."
- If the user wants a different schema name, they can set `pipeline_prefix` in the `--config` file:

```json
{
  "pipeline_prefix": "my_custom_schema",
  "is_custom_prefix": true
}
```

This is important because two pipelines writing to the same schema prefix will cause merge conflicts. Each pipeline should have its own unique prefix.

### What Happens During Create

1. Resolves source, destination, and project
2. Fetches the active pipeline version
3. Merges config defaults with overrides from `--config`
4. Inserts pipeline in draft state
5. Triggers schema discovery on the source
6. Saves object selections (all objects if `--objects` not provided)
7. Activates the pipeline

### Object Selection File

Generate with `datasources catalog --output`, then edit:

```json
[
  { "fully_qualified_name": "public.accounts", "selected": true, "fields": null },
  { "fully_qualified_name": "public.contacts", "selected": true, "fields": null },
  { "fully_qualified_name": "public.internal_logs", "selected": false, "fields": null }
]
```

- `fields: null` syncs all fields (recommended)
- To select specific fields: `"fields": [{ "name": "field_name", "selected": true }]`

### Pipeline Config File

Override defaults with a JSON file (only include fields to override):

```json
{
  "ingestion_mode": "HISTORICAL",
  "load_mode": "TRUNCATE_AND_LOAD",
  "schema_evolution_mode": "BLOCK_ALL",
  "perform_hard_deletes": true
}
```

### Configuration Options

| Setting | Default | Options |
|---------|---------|---------|
| `pipeline_type` | `REPLICATION` | `REPLICATION`, `ACTIVATION` |
| `ingestion_mode` | `HISTORICAL_PLUS_INCREMENTAL` | `HISTORICAL`, `INCREMENTAL`, `HISTORICAL_PLUS_INCREMENTAL` |
| `load_mode` | `MERGE` | `MERGE`, `APPEND`, `TRUNCATE_AND_LOAD`, `OVERWRITE` |
| `error_handling` | `MODERATE` | `STRICT`, `MODERATE` |
| `schema_evolution_mode` | `ALLOW_ALL` | `ALLOW_ALL`, `BLOCK_ALL`, `COLUMN_LEVEL_ONLY` |
| `destination_table_handling` | `MERGE` | `MERGE`, `FAIL`, `DROP` |
| `perform_hard_deletes` | `false` | `true`, `false` |
| `full_sync_frequency` | `WEEKLY` | `NEVER`, `DAILY`, `WEEKLY`, `MONTHLY`, `EVERY_RUN` |
| `full_resync_frequency` | `NEVER` | `NEVER`, `DAILY`, `WEEKLY`, `MONTHLY` |

Note: `ACTIVATION` pipelines always enforce `BLOCK_ALL` schema evolution.

### Pipeline Config vs Connector Properties

**Pipeline config** (set via `--config`) controls how data moves: ingestion mode, load mode, schema evolution, error handling, sync frequency. These are the settings in the table above.

**Connector properties** (set in the datasource env file) control how the connector connects and behaves at the source/destination level. These are NOT pipeline settings. Examples:
- **SQL Server**: Change Tracking (`changeTrackingEnabled`), CDC mode
- **S3/S3 Data Lake**: file format (Parquet, Iceberg, CSV), Glue catalog, bucket path
- **Snowflake**: warehouse, role, authentication method, database/schema
- **PostgreSQL**: replication slot, publication name, SSL mode

If the user asks about Change Tracking, Iceberg, Parquet, Glue, or other connector-specific features, inspect the datasource config with `datasources get <identifier> --json` and look at the `configs` object. Do NOT look for these in pipeline config.

For connector setup guides and available properties, fetch the Supaflow docs:
```bash
curl -s https://www.supa-flow.io/docs/llms/docs.txt
```

## Running a Pipeline

```bash
# Incremental sync (default)
supaflow pipelines sync <identifier> --json

# Full resync (reset cursors, re-sync all data)
supaflow pipelines sync <identifier> --full-resync --json

# Full resync + drop and recreate destination tables
supaflow pipelines sync <identifier> --full-resync --reset-target --json
```

The sync command returns:

```json
{ "job_id": "13cfe303-...", "pipeline_id": "3d72f887-...", "status": "queued" }
```

Monitor with lightweight polling, then get full details after completion:

```bash
# Poll (lightweight)
supaflow jobs status <job-id> --json

# Full details after terminal state
supaflow jobs get <job-id> --json
```

## Schema Management

View and update which objects a pipeline syncs:

```bash
# List selected objects (compact: object name, field counts, origin)
supaflow pipelines schema list <identifier> --json

# List all objects (including deselected)
supaflow pipelines schema list <identifier> --all --json

# Add a single object by name (no file needed)
supaflow pipelines schema add <identifier> Opportunity --json

# Update selections from a JSON file (for bulk changes)
supaflow pipelines schema select <identifier> --from objects.json --json
```

**Schema list JSON shape** (compact, no field arrays):
```json
{
  "data": [
    { "object": "Account", "selected": true, "total_fields": 72, "selected_fields": 72, "origin": "explicit" },
    { "object": "Lead", "selected": true, "total_fields": 45, "selected_fields": 45, "origin": "explicit" }
  ]
}
```

**To add a single object to a pipeline**, use `schema add` -- no need to export/edit/reimport a file:
```bash
supaflow pipelines schema add my_pipeline Opportunity --json
```

## Editing a Pipeline

```bash
# Update config
supaflow pipelines edit <identifier> --config pipeline-config.json --json

# Update name
supaflow pipelines edit <identifier> --name "New Name" --json

# Update description
supaflow pipelines edit <identifier> --description "Updated description" --json
```

Multiple flags can be combined in a single edit command.

## State Management

```bash
supaflow pipelines disable <identifier> --json
supaflow pipelines enable <identifier> --json
```

Disabled pipelines cannot be synced until re-enabled.

## Listing and Viewing

```bash
supaflow pipelines list --json
supaflow pipelines list --state active --json

# Sorting and pagination
supaflow pipelines list --sort last_sync_at --order desc --json
supaflow pipelines list --limit 10 --offset 0 --json

supaflow pipelines get <identifier> --json
```

`pipelines get` includes the full `configs` object with all pipeline settings (ingestion_mode, load_mode, schema_evolution_mode, pipeline_prefix, etc.).

## Deletion

```bash
supaflow pipelines delete <identifier> --json

# Skip confirmation prompt (for agent workflows)
supaflow pipelines delete <identifier> --yes --json
```

## Identifier Resolution

Pipeline commands accept either a UUID or api_name:

```bash
supaflow pipelines get production_to_warehouse
supaflow pipelines sync production_to_warehouse --json
```

## Common Agent Patterns

### Create pipeline with selected objects

```bash
supaflow datasources catalog my_postgres --output objects.json
# Programmatically edit objects.json to set selected: true/false
supaflow pipelines create --name "My Pipeline" --source my_postgres --project analytics --objects objects.json --json
```

### Trigger sync and monitor

```bash
supaflow pipelines sync my_pipeline --json
# Returns: { "job_id": "...", "pipeline_id": "...", "status": "queued" }

# Poll with lightweight status
supaflow jobs status <job-id> --json
# Full details after terminal state
supaflow jobs get <job-id> --json
```

### Full resync after schema changes

```bash
supaflow pipelines sync my_pipeline --full-resync --reset-target --json
```
