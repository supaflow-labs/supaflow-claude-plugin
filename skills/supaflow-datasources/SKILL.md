---
name: supaflow-datasources
description: This skill should be used when the user asks to "create a datasource", "connect to a database", "set up a connection", "test a datasource", "browse catalog", "discover schema", "refresh schema", "edit datasource credentials", "encrypt secrets", "init datasource", "disable datasource", "enable datasource", "delete datasource", or mentions Supaflow datasources, connectors, connection configuration, env files, or listing source tables. Covers the full datasource lifecycle in the @getsupaflow/cli.
---

# Supaflow Datasource Management

**AGENT BEHAVIOR:**
- **Execute all CLI commands directly via Bash.** Do NOT ask the user to run commands manually.
- **Preserve context window.** Pipe `--json` output through `python3 -c` to extract only the fields you need. NEVER dump full JSON into the conversation. For catalog (can be 100s of objects), always use `--output <file>` and parse with a script.
- **ALWAYS run `datasources list` FIRST** before asking for any credentials or creating anything. Tell the user what datasources already exist and ask which to reuse. Only create what's missing.
- **Before asking for connection details, ask the user if they already have credentials in a file** (e.g., `.env`, `config.json`, `credentials.yaml`). If yes, read the file to extract values -- this is much faster than typing each field. If no, ask for non-sensitive fields in chat.
- **NEVER ask for all credentials upfront.** Work step by step: scaffold the env file first, read the annotations to learn which fields are required/sensitive, then ask only for what's needed.
- **NEVER ask for passwords or secrets in chat.** The generated env file marks each property with annotations in comments: `(required)`, `(optional)`, `(sensitive)`. Read the env file to identify which fields are sensitive vs non-sensitive. Then:
  1. Ask: "Do you have connection credentials in a file already (e.g., .env, config file)? If so, share the path. Otherwise I'll ask for the details."
  2. If user has a file: read it, extract matching property values, fill into the env file
  3. If no file: ask for all **non-sensitive required fields** in chat (host, port, database, username, etc.) and fill via Edit tool
  4. For **sensitive fields**: tell the user which ones still need to be filled: "I've filled in the connection details. Please open `<filename>.env` and add these sensitive fields: `password`. Type `done` when ready."
  5. Optionally open the file for them: `open <filename>.env` (macOS) or suggest `! $EDITOR <filename>.env`
  6. Once user confirms, run `datasources create --from <file>` which auto-encrypts sensitive fields on disk

**Env file annotation format:**
```env
# Database Host (required)          <-- non-sensitive, ask in chat
host=
# Password (required, sensitive)    <-- sensitive, user fills manually
password=
# SSL Mode (optional)               <-- optional, use default
sslMode=prefer
```

Manage datasource connections to external systems (databases, APIs, cloud storage). Each datasource stores encrypted connection credentials and discovers the source schema automatically.

All commands require prior authentication and workspace selection (see the supaflow-auth skill).

## Connector Setup Guides

Each connector may require prerequisites (user accounts, permissions, network access, API keys). If the user needs help with setup, **fetch the Supaflow docs** which contain connector-specific setup guides with SQL scripts, configuration steps, and required permissions:

```bash
# Fetch docs to a temp file (single markdown file, ~380KB, ~11K lines)
curl -s https://www.supa-flow.io/docs/llms/docs.txt > /tmp/supaflow-docs.txt

# Do NOT load the entire file -- search for the relevant connector section:
grep -n "Source: .*sqlserver\|Source: .*snowflake\|Source: .*postgres" /tmp/supaflow-docs.txt
# Then read only that section with sed -n 'START,ENDp' /tmp/supaflow-docs.txt
```

Each doc page is delimited by `<!-- Source: URL -->` comments. Read only the sections relevant to the user's connectors. The docs contain:
- Required database users and permissions (e.g., CREATE USER, GRANT SELECT)
- Snowflake warehouse/role setup scripts
- S3 bucket and IAM role configuration
- OAuth app setup for Salesforce/HubSpot
- Network access and firewall rules
- **Connector-specific properties** (Query Mode for SQL Server, replication for PostgreSQL, etc.)

If the user hasn't set up the source/destination system yet, fetch the docs and help them through the setup before creating the datasource in Supaflow.

**Connector properties vs pipeline config:** Features like Change Tracking (SQL Server), Iceberg/Parquet/Glue (S3), CDC mode (PostgreSQL), and authentication method are **connector properties** -- they live in the datasource config, NOT in the pipeline. Use `datasources get <id> --json` to inspect them. Pipeline config only controls ingestion mode, load mode, schema evolution, etc.

## Before Creating a Datasource (MANDATORY)

**ALWAYS run `datasources list` FIRST. This is not optional.** Do this before asking the user for ANY connection details.

```bash
supaflow datasources list --json | python3 -c "
import sys,json; d=json.load(sys.stdin)
if 'error' in d: print(d['error']['message']); sys.exit(1)
for ds in d['data']:
    print(f\"{ds['name']} | {ds['connector_type']} | api_name={ds['api_name']} | state={ds['state']}\")
"
```

**Important:** List commands return `{ "data": [...] }` -- always access `['data']` to get the array.

Review the list and tell the user what already exists. For example:
- "You already have a SQL Server source called 'SQL Server' (api_name: sql_server_qdvbd4). Want to use it or create a new one?"
- "You have 3 Snowflake destinations. Which one should I use for this pipeline?"

**Only proceed with creation if no suitable datasource exists or the user explicitly wants a new one.** Do NOT ask for credentials before checking.

**When reusing an existing datasource:** If the user mentioned connector-specific features (Change Tracking, CDC, Iceberg, Parquet, etc.), run `datasources get <api_name> --json` to inspect the `configs` object and verify the feature is enabled BEFORE proceeding. Do NOT assume existing datasources have the right settings.

## Datasource Creation (Two-Step Process)

### Step 1: Scaffold the Env File

Generate a connector-specific env file with all available properties:

```bash
supaflow datasources init --connector <TYPE> --name "<Display Name>" --json

# Optionally specify the output file path
supaflow datasources init --connector <TYPE> --name "<Display Name>" --output my_source.env --json
```

This creates a file named after the api_name (e.g., `my_postgres.env`) unless `--output` is specified. The file contains annotated properties grouped by category, with defaults pre-filled.

Init JSON output:
```json
{
  "file": "my_postgres.env",
  "name": "My Postgres",
  "api_name": "my_postgres",
  "connector": "POSTGRES",
  "connector_version": "1.0.46-SNAPSHOT",
  "required_properties": 5,
  "optional_properties": 10
}
```

Available connector types can be listed with:

```bash
supaflow connectors list --json
```

Common types: `POSTGRES`, `SNOWFLAKE`, `S3`, `HUBSPOT`, `SALESFORCE`, `AIRTABLE`, `ORACLE_TM`, `SFMC`, `SQL_SERVER`, `GOOGLE_DRIVE`.

### Step 2: Fill Values and Create

Edit the generated env file with connection details. Use `${VAR}` references for secrets to avoid storing them in cleartext:

```env
host=db.example.com
port=5432
database=mydb
username=${DB_USER}
password=${DB_PASSWORD}
```

`${VAR}` references are resolved from the current shell environment at create time. If a plaintext secret is present, the CLI auto-encrypts it on disk before submission (the file is rewritten with `enc:` prefixed values).

Create the datasource:

```bash
supaflow datasources create --from <filename>.env --json
```

This tests the connection first and only saves on success. The test may take up to a minute. On success, returns the created datasource object with its UUID and api_name.

## Browsing the Catalog

After creation, the platform discovers the source schema (tables, objects).

### Recommended workflow: export to file, read file, summarize for user

**Always use `--output` to write the catalog to a file.** Do NOT try to parse object names from the `--json` stdout -- stdout only returns metadata. The objects are in the file.

```bash
# Step 1: Export catalog to file
supaflow datasources catalog <identifier> --output /tmp/objects.json --json
# stdout returns: { "file": "/tmp/objects.json", "datasource": "SQL Server", "objects": 7 }
# The "objects" field is an INTEGER COUNT, not a list. The actual objects are in the FILE.

# Step 2: Read the file and summarize for the user (catalogs can have 100s of objects)
python3 -c "
import json
objs = json.load(open('/tmp/objects.json'))
print(f'Found {len(objs)} objects:')
for o in objs:
    print(f\"  {o['fully_qualified_name']}\")
"

# Step 3: Ask user which objects to exclude, then deselect them
python3 -c "
import json
objs = json.load(open('/tmp/objects.json'))
skip = {'MSchange_tracking_history', 'sys.trace_xe_action_map', 'sys.trace_xe_event_map'}
for o in objs:
    if any(s in o['fully_qualified_name'] for s in skip):
        o['selected'] = False
json.dump(objs, open('/tmp/objects.json','w'), indent=2)
print('Updated selections:')
for o in objs:
    print(f\"  {o['fully_qualified_name']} -> {'SELECTED' if o['selected'] else 'excluded'}\")
"

# Step 4: Pass to pipeline create
supaflow pipelines create ... --objects /tmp/objects.json --json
```

To trigger fresh discovery before export:
```bash
supaflow datasources catalog <identifier> --refresh --output /tmp/objects.json --json
```

**File format** (JSON array, NOT wrapped in `{ "data": [...] }`):
```json
[
  { "fully_qualified_name": "public.accounts", "selected": true, "fields": null },
  { "fully_qualified_name": "public.contacts", "selected": true, "fields": null }
]
```

Each object has exactly 3 keys: `fully_qualified_name`, `selected`, `fields`. There is no `name` or `namespace` field.
- `selected: true` includes the object in the pipeline
- `selected: false` excludes it
- `fields: null` syncs all fields (recommended)

**Tip: To add a single object to an existing pipeline, use `pipelines schema add` directly instead of exporting the full catalog:**
```bash
supaflow pipelines schema add <pipeline> Opportunity --json
```

## Listing and Viewing Datasources

```bash
# List all datasources (no configs -- lightweight)
supaflow datasources list --json

# View details by UUID or api_name (includes configs)
supaflow datasources get <identifier> --json
```

List output follows the standard contract: `{ "data": [...], "total": N, "limit": N, "offset": N }`.

**`datasources get` includes `configs`** -- the full connector configuration. Use this to inspect how a datasource is configured (e.g., whether SQL Server uses Change Tracking, what auth method is used, which database/host is connected):

```json
{
  "id": "...",
  "name": "SQL Server",
  "connector_type": "SQLSERVER",
  "configs": {
    "host": "10.0.1.50",
    "port": "1433",
    "database": "SalesDB",
    "username": "supaflow_reader",
    "password": { "v": 1, "fp": "abc...", "data": "..." },
    "queryMode": "CHANGE_TRACKING",
    "sslMode": "require"
  }
}
```

Sensitive values are stored as **encrypted envelopes** (`{ "v", "fp", "data" }`). These are safe to return -- only the pipeline agent has the private key. When editing, send unchanged envelopes back as-is; only replace values that actually changed.

## Testing a Connection

Re-test an existing datasource's connection:

```bash
supaflow datasources test <identifier> --json
```

Creates an async job. The command returns when the test completes. If the datasource was created with empty configs, edit it first with valid connection details.

## Editing a Datasource

Update credentials or configuration from a new env file:

```bash
# Edit with connection test (default)
supaflow datasources edit <identifier> --from <file>.env --json

# Edit without testing
supaflow datasources edit <identifier> --from <file>.env --skip-test --json
```

**Important:** The edit command replaces the **entire** configs object, not individual fields. To safely edit, export the current config as an env file first:

```bash
# Export current config as env file (encrypted values preserved as enc: format)
supaflow datasources get <identifier> --output current.env

# Edit only the values that need to change (encrypted values pass through unchanged)
# Then submit:
supaflow datasources edit <identifier> --from current.env --json
```

The `--output` flag on `datasources get` produces a complete env file with all properties, annotations, and current values pre-filled. Encrypted sensitive values are encoded as `enc:` prefixed strings that can be sent back as-is.

## Schema Refresh

Trigger a fresh schema discovery on the source:

```bash
supaflow datasources refresh <identifier> --json
```

This creates an async discovery job. New or changed objects appear in the catalog after the job completes.

## State Management

Disable or enable a datasource without deleting it:

```bash
supaflow datasources disable <identifier> --json
supaflow datasources enable <identifier> --json
```

Disabled datasources cannot be used by pipelines until re-enabled.

## Deletion

Soft-delete a datasource:

```bash
supaflow datasources delete <identifier> --json
```

## Encrypting Sensitive Values

Encrypt values manually for use in env files:

```bash
# Encrypt a single value
supaflow encrypt "my-secret" --json

# Encrypt all sensitive fields in an env file
supaflow encrypt --file <filename>.env
```

The `enc:` prefix marks already-encrypted values. Both `datasources create` and `datasources edit` pass encrypted values through without re-encryption.

## Identifier Resolution

All datasource commands accept either a UUID or an api_name:

```bash
supaflow datasources get 8a3f1b2c-4d5e-6f7a-8b9c-0d1e2f3a4b5c
supaflow datasources get my_postgres
```

## Common Patterns for Agents

### Create a datasource non-interactively

```bash
supaflow datasources init --connector postgres --name "My Postgres" --json
# Edit the env file programmatically
supaflow datasources create --from my_postgres.env --json
```

### Export catalog for pipeline creation

```bash
supaflow datasources catalog my_postgres --output objects.json
# Edit objects.json to toggle selections
```

### Check if a datasource exists before creating

```bash
supaflow datasources list --json
# Parse output to check for existing api_name
```

## Error Handling

All errors with `--json` return: `{ "error": { "code": "...", "message": "..." } }`.

Common datasource errors:
- `NOT_FOUND`: Datasource identifier does not exist in the workspace
- `INVALID_INPUT`: Missing required env file fields or bad connector type
- `API_ERROR`: Connection test failed (check credentials and network)
- "configs cannot be NULL or empty": Edit the datasource with valid connection details first
