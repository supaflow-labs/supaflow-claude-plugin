---
name: supaflow-pipelines
description: This skill should be used when the user asks to "create a pipeline", "sync data", "run a pipeline", "full resync", "reset target", "edit pipeline config", "select objects", "manage schema", "set ingestion mode", "configure load mode", "pipeline settings", "disable pipeline", "enable pipeline", "delete pipeline", "list pipelines", or mentions Supaflow pipelines, data replication, object selection, or pipeline configuration. Covers the full pipeline lifecycle including schema management in the @getsupaflow/cli.
---

# Supaflow Pipeline Management

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

The `--destination` flag accepts a datasource UUID or api_name. Project type defaults to `pipeline`.

## Before Creating a Pipeline

**Always check for existing pipelines between the same source and destination first.** Duplicate pipelines writing to the same destination schema cause merge conflicts and data corruption.

```bash
supaflow pipelines list --json
```

Review the results for pipelines with the same source and destination. If one exists, inform the user:
- What pipeline already exists (name, source, destination)
- What objects it syncs (`supaflow pipelines schema list <identifier> --json`)
- Offer to **edit** the existing pipeline or **add objects** to it instead of creating a new one
- If the user still wants a new pipeline, warn that it should use different objects or a different destination schema prefix to avoid writing to the same tables

Only create a new pipeline if no existing pipeline covers the same source-destination pair, or the user explicitly confirms they want a separate one.

## Creating a Pipeline

```bash
# Minimal: all discovered objects selected
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

The `--source` and `--project` flags accept UUID or api_name. The destination is resolved from the project.

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

## Running a Pipeline

```bash
# Incremental sync (default)
supaflow pipelines sync <identifier> --json

# Full resync (reset cursors, re-sync all data)
supaflow pipelines sync <identifier> --full-resync --json

# Full resync + drop and recreate destination tables
supaflow pipelines sync <identifier> --full-resync --reset-target --json
```

The sync command returns a job ID. Monitor with:

```bash
supaflow jobs get <job-id> --json
```

## Schema Management

View and update which objects a pipeline syncs:

```bash
# List selected objects
supaflow pipelines schema list <identifier> --json

# List all objects (including deselected)
supaflow pipelines schema list <identifier> --all --json

# Update selections from a JSON file
supaflow pipelines schema select <identifier> --from objects.json --json
```

## Editing a Pipeline

```bash
# Update config
supaflow pipelines edit <identifier> --config pipeline-config.json --json

# Update name
supaflow pipelines edit <identifier> --name "New Name" --json
```

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
supaflow pipelines get <identifier> --json
```

## Deletion

```bash
supaflow pipelines delete <identifier> --json
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
JOB=$(supaflow pipelines sync my_pipeline --json)
# Extract job ID from output, then:
supaflow jobs get <job-id> --json
```

### Full resync after schema changes

```bash
supaflow pipelines sync my_pipeline --full-resync --reset-target --json
```
