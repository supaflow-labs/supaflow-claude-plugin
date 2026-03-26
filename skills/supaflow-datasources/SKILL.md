---
name: supaflow-datasources
description: This skill should be used when the user asks to "create a datasource", "connect to a database", "set up a connection", "test a datasource", "browse catalog", "discover schema", "refresh schema", "edit datasource credentials", "encrypt secrets", "init datasource", "disable datasource", "enable datasource", "delete datasource", or mentions Supaflow datasources, connectors, connection configuration, env files, or listing source tables. Covers the full datasource lifecycle in the @getsupaflow/cli.
---

# Supaflow Datasource Management

**AGENT BEHAVIOR:**
- **Execute all CLI commands directly via Bash.** Do NOT ask the user to run commands manually.
- **Preserve context window.** Pipe `--json` output through `python3 -c` to extract only the fields you need. NEVER dump full JSON into the conversation. For catalog (can be 100s of objects), always use `--output <file>` and parse with a script.
- **Only ask the user for:** non-sensitive connection details (host, port, database, username, etc.).
- **NEVER ask for passwords or secrets in chat.** Instead, fill in all non-sensitive fields in the env file, then ask the user to add sensitive fields themselves:
  1. Fill non-sensitive fields in the env file via Edit tool
  2. Tell the user: "I've filled in the connection details. Please open `<filename>.env` and add the password/secret fields marked `(sensitive)`. Type `done` when ready."
  3. Optionally open the file for them: `open <filename>.env` (macOS) or suggest `! $EDITOR <filename>.env`
  4. Once user confirms, run `datasources create --from <file>` which auto-encrypts sensitive fields on disk

Manage datasource connections to external systems (databases, APIs, cloud storage). Each datasource stores encrypted connection credentials and discovers the source schema automatically.

All commands require prior authentication and workspace selection (see the supaflow-auth skill).

## Before Creating a Datasource

**Always check if a matching datasource already exists first.** The user may already have a connection to the system they want to use.

```bash
supaflow datasources list --json
```

Look for an existing datasource with the same connector type and ask the user before creating a duplicate. For example, if the user says "connect to Salesforce" and there is already a Salesforce datasource, ask: "You already have a Salesforce datasource named 'Salesforce Prod'. Do you want to use that one, or create a new connection?"

Only proceed with creation if no suitable datasource exists or the user explicitly wants a new one.

## Datasource Creation (Two-Step Process)

### Step 1: Scaffold the Env File

Generate a connector-specific env file with all available properties:

```bash
supaflow datasources init --connector <TYPE> --name "<Display Name>" --json
```

This creates a file named after the api_name (e.g., `my_postgres.env`). The file contains annotated properties grouped by category, with defaults pre-filled.

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

After creation, the platform discovers the source schema (tables, objects). Browse and export:

```bash
# List discovered objects
supaflow datasources catalog <identifier> --json

# Export as JSON for pipeline creation
supaflow datasources catalog <identifier> --output objects.json

# Trigger fresh discovery first, then export
supaflow datasources catalog <identifier> --refresh --output objects.json
```

The exported `objects.json` can be edited (toggle `"selected": false` for objects to exclude) and passed to `pipelines create --objects`.

**Catalog JSON field**: each object has `fully_qualified_name` (the key to use everywhere). To find a specific object:
```bash
supaflow datasources catalog <identifier> --json | python3 -c "
import sys,json
for o in json.load(sys.stdin)['data']:
    if 'opportunity' in o['fully_qualified_name'].lower():
        print(o['fully_qualified_name'])
"
```

**Tip: To add a single object to an existing pipeline, use `pipelines schema add` directly instead of exporting the full catalog:**
```bash
supaflow pipelines schema add <pipeline> Opportunity --json
```

Export format:

```json
[
  { "fully_qualified_name": "public.accounts", "selected": true, "fields": null },
  { "fully_qualified_name": "public.contacts", "selected": true, "fields": null },
  { "fully_qualified_name": "public.internal_logs", "selected": false, "fields": null }
]
```

- `selected: true` includes the object in the pipeline
- `selected: false` excludes it
- `fields: null` syncs all fields (recommended)

## Listing and Viewing Datasources

```bash
# List all datasources
supaflow datasources list --json

# View details by UUID or api_name
supaflow datasources get <identifier> --json
```

List output follows the standard contract: `{ "data": [...], "total": N, "limit": N, "offset": N }`.

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

Only the fields present in the env file are updated. Omitted fields retain their current values.

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
