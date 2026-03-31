---
name: supaflow-pipelines
description: Use when you need reference information about Supaflow pipeline configuration, schema management, sync modes, object selection, or pipeline lifecycle
---

# Supaflow Pipeline Management

**This is a reference skill, not a workflow.** For pipeline operations, use `/create-pipeline`, `/edit-pipeline`, or `/delete-pipeline` commands. This skill provides background knowledge about pipeline config fields, schema management, and sync modes.

Pipelines move data from a source datasource to a destination warehouse. Each pipeline belongs to a project (which defines the destination) and selects which objects to sync.

All CLI commands require authentication and an active workspace.

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

## Pipeline Configuration Options

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
- If the user still wants a new pipeline, warn that it should use different objects or a different destination schema prefix to avoid writing to the same tables, then ask for explicit confirmation

Only create a new pipeline if no existing pipeline covers the same source-destination pair, or the user explicitly confirms they want a separate one.

## Pipeline Create CLI Reference

Before running `pipelines create`, read source and destination capabilities to determine which options are valid. Do NOT silently use defaults. Do NOT show options the connectors don't support.

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

### Config Value Examples

Example of how config values look with valid options from capabilities:

```
Destination schema prefix: sqlserver (lowercased source connector type)
  ** Cannot be changed after creation **

Ingestion mode: HISTORICAL_PLUS_INCREMENTAL (default)
  Other options: INCREMENTAL, HISTORICAL

Load mode: MERGE (default)
  Other options: APPEND, TRUNCATE_AND_LOAD, OVERWRITE

Schema evolution: ALLOW_ALL (default)
  Other options: BLOCK_ALL, COLUMN_LEVEL_ONLY

```

The `/create-pipeline` command handles presenting these options and collecting user confirmation.

### Pipeline Prefix (Destination Schema Name)

The default prefix is the **lowercased source connector type** (e.g., `sqlserver`, `postgres`, `hubspot`).

When presenting options, compute the default: take the source datasource's `connector_type` from `datasources list` and lowercase it.

- If user accepts the default: leave `pipeline_prefix` empty (or omit the config file) -- the system generates it automatically
- If user wants a custom prefix: set **`pipeline_prefix`** and **`is_custom_prefix: true`** in the config file

**Config file field names** (use EXACTLY these snake_case names -- the CLI rejects unknown fields):
```json
{
  "pipeline_prefix": "my_custom_schema",
  "is_custom_prefix": true,
  "ingestion_mode": "INCREMENTAL",
  "load_mode": "APPEND",
  "schema_evolution_mode": "BLOCK_ALL"
}
```

**Do NOT use camelCase** (e.g., `destinationSchemaPrefix`, `loadMode`, `ingestionMode`). The backend uses `@JsonNaming(SnakeCaseStrategy)` and will crash on unrecognized fields. All valid field names: `pipeline_prefix`, `is_custom_prefix`, `ingestion_mode`, `load_mode`, `schema_evolution_mode`, `error_handling`, `perform_hard_deletes`, `full_sync_frequency`, `full_resync_frequency`, `destination_table_handling`, `namespace_rules`, `pipeline_type`, `load_optimization_mode`, `checksum_validation_level`.

Write the config file as a **separate command** before `pipelines create`:
```bash
# Step 1: Write config file
echo '{"pipeline_prefix": "my_custom_schema", "is_custom_prefix": true}' > /tmp/pipeline-config.json

# Step 2: Create pipeline (separate command)
supaflow pipelines create --name "..." --source ... --project ... --config /tmp/pipeline-config.json --json
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

The destination schema name defaults to the lowercased source connector type (e.g., `salesforce`, `postgres`, `hubspot`) unless the user sets a custom prefix.

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
- **SQL Server**: Change Tracking (`queryMode: CHANGE_TRACKING`), CDC mode
- **S3/S3 Data Lake**: file format (Parquet, Iceberg, CSV), Glue catalog, bucket path
- **Snowflake**: warehouse, role, authentication method, database/schema
- **PostgreSQL**: replication slot, publication name, SSL mode

If the user asks about Change Tracking, Iceberg, Parquet, Glue, or other connector-specific features, inspect the datasource config with `datasources get <identifier> --json` and look at the `configs` object. Do NOT look for these in pipeline config.

For connector setup guides and available properties:
```bash
supaflow docs <connector-type> --output /tmp/<connector>-docs.txt
# Then read the relevant sections from the file
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
# List selected objects (import-ready format)
supaflow pipelines schema list <identifier> --json

# List all objects (including deselected)
supaflow pipelines schema list <identifier> --all --json

# Add a single object by name (no file needed)
supaflow pipelines schema add <identifier> Opportunity --json

# Roundtrip: export, edit, reimport
supaflow pipelines schema list <identifier> --all --json > objects.json
# Edit objects.json (toggle selected: true/false)
supaflow pipelines schema select <identifier> --from objects.json --json
```

**Schema list JSON shape** -- returns a raw array (NOT wrapped in `{ data: [...] }`). Uses `fully_qualified_name`:
```json
[
  { "fully_qualified_name": "Account", "selected": true, "fields": null },
  { "fully_qualified_name": "Lead", "selected": true, "fields": null }
]
```

This is the same shape consumed by `schema select --from` and `pipelines create --objects`.

**Parsing example:**
```bash
supaflow pipelines schema list <identifier> --all --json | python3 -c "
import sys,json; objs=json.load(sys.stdin)
if isinstance(objs, dict) and 'error' in objs: print(objs['error']['message']); sys.exit(1)
for o in objs:
    sel = 'SELECTED' if o['selected'] else 'excluded'
    print(f\"  {o['fully_qualified_name']} | {sel}\")
"
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

## Common Operations

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

### Verify selected objects after create

Before the first sync of a newly created pipeline, verify the actual selected objects:

```bash
supaflow pipelines schema list <identifier> --json
```

Treat `pipelines schema list` as the source of truth for selection. Do NOT assume summary fields from `pipelines create` prove which objects are selected.

### Full resync after schema changes

```bash
supaflow pipelines sync my_pipeline --full-resync --reset-target --json
```
