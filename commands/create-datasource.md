---
description: Connect a new data source
allowed-tools: Bash(supaflow *), Bash(snow *), Bash(aws *), Bash(gcloud *), Bash(az *), Bash(psql *), Bash(sqlcmd *), Bash(mysql *), Read, Edit, Write
argument-hint: [connector-type]
---

# Create Supaflow Datasource

You are helping the user create a new Supaflow datasource. Follow these steps exactly and in order. Do NOT skip steps.

## Step 1: Setup Check

Run the auth status check first. If it fails, STOP immediately -- do not proceed.

```bash
supaflow auth status --json | python3 -c "
import sys,json; d=json.load(sys.stdin)
if 'error' in d: print('ERROR: ' + d['error']['message']); sys.exit(1)
if not d.get('authenticated'): print('Not authenticated. Run: supaflow auth login'); sys.exit(1)
if not d.get('workspace_id'): print('No workspace selected. Run: supaflow workspaces select'); sys.exit(1)
print(f\"Authenticated | Workspace: {d.get('workspace_name','unknown')} ({d.get('workspace_id','')})\")
"
```

If authentication or workspace check fails: STOP. Tell the user to run `supaflow auth login` and/or `supaflow workspaces select`, then retry the command.

Do NOT proceed to Step 2 until Step 1 succeeds.

Cannot run `npm install` -- this command is tool-restricted.

## Step 2: Resolve Connector Type and Read Documentation

**MUST read the connector doc FIRST -- before checking existing datasources or asking for any config.** The doc is the source of truth for prerequisites, required credentials, and connector-specific caveats. Reading it first ensures you know what to look for when inspecting existing datasources.

1. Resolve the connector type. If the user passed `[connector-type]` as an argument, use that. If not, ask. Map common names to doc topics: `sql_server` -> `sqlserver`, `s3` -> `s3` or `s3-data-lake`, `postgres` -> `postgres`, etc.

2. Fetch and save the connector doc:
```bash
supaflow docs <connector-type> --output /tmp/<connector>-docs.txt
```

3. Read the full saved file to understand:
   - **Prerequisites** (IAM roles, firewall rules, database users, permissions, network access)
   - **Required credentials** (what the user needs to provide)
   - **Connector-specific caveats** (query modes, auth methods, special setup)

4. Present the prerequisites to the user as a checklist. For example:
```
Before creating this datasource, these prerequisites must be in place:

- [ ] AWS IAM role with S3 read/write permissions (cross-account trust policy)
- [ ] S3 bucket exists and is accessible
- [ ] Glue Data Catalog permissions (if using catalog registration)

Are these already done, or do you need help setting any of them up?
```

5. Wait for the user's response:
   - **All done:** Proceed to Step 3.
   - **Need help:** Walk the user through the prerequisite steps using the doc content. This command can run prerequisite CLIs directly:
     - `snow sql` -- Snowflake user/role/warehouse/database creation
     - `aws iam`, `aws s3` -- IAM roles, S3 bucket policies
     - `gcloud` -- GCP service accounts, permissions
     - `az` -- Azure resource configuration
     - `psql` -- PostgreSQL user/permission setup
     - `sqlcmd` -- SQL Server user/permission setup
     - `mysql` -- MySQL user/permission setup
     Execute the prerequisite commands from the docs when the user confirms. Ask before running each destructive operation (CREATE ROLE, CREATE USER, etc.).
   - **Explicitly deferred:** The user says "skip prerequisites" or "I'll handle that later." Acknowledge the risk and proceed to Step 3.

**GUARDRAIL: Do NOT proceed to datasource creation until prerequisites are confirmed complete or explicitly deferred by the user.**

**GUARDRAIL: Save docs to a file and read locally. Do NOT dump full doc content into the conversation.**

## Step 3: Check Existing Datasources

**Run this AFTER reading docs so you know what to look for** (e.g., whether an existing datasource has the right query mode or auth method).

```bash
supaflow datasources list --limit 200 --json | python3 -c "
import sys,json; d=json.load(sys.stdin)
if 'error' in d: print('ERROR: ' + d['error']['message']); sys.exit(1)
items = d.get('data', [])
if not items: print('No existing datasources found.')
else:
    total = d.get('total', len(items))
    print(f'Found {total} existing datasource(s):')
    for ds in items:
        print(f\"  {ds['name']} | connector={ds.get('connector_type','?')} | api_name={ds.get('api_name','?')} | state={ds.get('state','?')}\")
    if total > len(items):
        print(f'WARNING: showing {len(items)} of {total} datasources. Use --offset to page.')
"
```

- If a datasource of the requested type already exists, tell the user and ask: "You already have a `<TYPE>` datasource called `<name>`. Would you like to reuse it, or create a new one?"
- If multiple same-type datasources exist, list all and ask which to use. NEVER assume.
- If the user wants to reuse: STOP here -- no need to create.
- Only continue to Step 4 if the user confirms they want a new datasource.

**When reusing an existing datasource:** Use the connector doc knowledge from Step 2 to verify the existing datasource has the right settings. Run `datasources get <api_name> --json` and check connector-specific config properties (e.g., `queryMode: CHANGE_TRACKING` for SQL Server CT).

**GUARDRAIL: You MUST NOT ask for any connection credentials before completing this step.**

## Step 4: Scaffold the Env File

Determine the connector type (already resolved in Step 2).

Common connector types: `POSTGRES`, `SNOWFLAKE`, `S3`, `HUBSPOT`, `SALESFORCE`, `AIRTABLE`, `ORACLE_TM`, `SFMC`, `SQL_SERVER`, `GOOGLE_DRIVE`.

To see all available connector types:

```bash
supaflow connectors list --json | python3 -c "
import sys,json; d=json.load(sys.stdin)
if 'error' in d: print(d['error']['message']); sys.exit(1)
for c in d.get('data', []):
    print(f\"{c['type']} | {c['name']} | {', '.join(c.get('capabilities', []))}\")
"
```

Once you have the connector type and a display name from the user, scaffold the env file:

```bash
supaflow datasources init --connector <CONNECTOR_TYPE> --name "<Display Name>" --json | python3 -c "
import sys,json; d=json.load(sys.stdin)
if 'error' in d: print('ERROR: ' + d['error']['message']); sys.exit(1)
print(f\"Scaffolded: {d['file']}\")
print(f\"api_name: {d['api_name']}\")
print(f\"Required fields: {d['required_properties']} | Optional fields: {d['optional_properties']}\")
"
```

Note the env file path from the output.

## Step 5: Read the Env File and Identify Fields

Read the scaffolded env file to understand which fields are required, optional, and sensitive:

Use the Read tool to read the env file. Look for annotation comments in this format:

```env
# Database Host (required)          <-- non-sensitive, ask in chat
host=
# Password (required, sensitive)    <-- sensitive, user fills manually
password=
# SSL Mode (optional)               <-- optional, use default
sslMode=prefer
```

Categorize each field:
- `(required)` and NOT `(sensitive)` -- you will ask for these in chat
- `(required, sensitive)` or just `(sensitive)` -- user must fill these directly in the file; NEVER ask in chat
- `(optional)` -- use default if present, or skip

## Step 6: Ask About Existing Credentials File

Before asking for any values, ask the user:

"Do you have connection credentials in an existing file (e.g., `.env`, `config.json`, `credentials.yaml`, or a cloud provider config)? If so, please share the path and I'll extract the values automatically."

- If yes: Use the Read tool to read their file. Extract values matching the env file properties. Fill in non-sensitive values using the Edit tool.
- If no: Ask for non-sensitive required fields **one at a time**. This is an exception-free application of the one-question-at-a-time rule -- do not batch credential questions. Fill each value using the Edit tool as the user provides it.

**GUARDRAIL: NEVER ask for passwords, secrets, API keys, tokens, private keys, or any field marked `(sensitive)` in chat.**

## Step 7: Handle Sensitive Fields

After filling in non-sensitive values, identify which sensitive fields are still empty in the env file.

Tell the user exactly which fields they need to fill:

"I've filled in the connection details. Please open `<filename>.env` directly and add values for these sensitive fields:
- `password` (required, sensitive)
- `clientSecret` (required, sensitive)

Type `done` when you have saved the file."

Wait for the user to confirm before proceeding. Do NOT move to Step 8 until they say done.

Optionally suggest: `open <filename>.env` (macOS) to open the file in their default editor.

## Step 8: Final Confirmation and Create

Present a summary of what will be created and wait for explicit approval:

```
Ready to create datasource:

Name:           <DISPLAY_NAME>
Connector:      <CONNECTOR_TYPE>
Key settings:   host=<value>, port=<value>, database=<value>, ...
Sensitive:      <N> fields filled by user in env file
Env file:       <filename>.env

Proceed with creation?
```

**Do NOT run `datasources create` until the user explicitly confirms.** This is a hard gate matching the plugin's "do not create before explicit confirmation" rule.

Once confirmed:

```bash
supaflow datasources create --from <ENV_FILE> --json | python3 -c "
import sys,json; d=json.load(sys.stdin)
if 'error' in d: print('ERROR: ' + d['error']['message']); sys.exit(1)
print(f\"Created datasource: {d.get('name')} (api_name={d.get('api_name')}, id={d.get('id')})\")
print(f\"State: {d.get('state')} | Connector: {d.get('connector_type')}\")
"
```

The create command auto-encrypts any plaintext sensitive values in the env file before submission. On success it returns the created datasource object with id and api_name.

If creation fails with an auth or workspace error, stop and recheck Step 1.

## Step 9: Test the Connection and Verify Readiness

After creation, trigger a connection test and poll for the result:

```bash
supaflow datasources test <NAME_OR_API_NAME> --json | python3 -c "
import sys,json; d=json.load(sys.stdin)
if 'error' in d: print('ERROR: ' + d['error']['message']); sys.exit(1)
print(f\"Test job started: {d.get('job_id','unknown')}\")
"
```

Poll the job status using only the 4 fields returned by `jobs status` (`id`, `job_status`, `status_message`, `job_response`):

```bash
supaflow jobs status <JOB_ID> --json | python3 -c "
import sys,json; d=json.load(sys.stdin)
if 'error' in d: print(d['error']['message']); sys.exit(1)
job_st = d['job_status']
msg = d.get('status_message') or ''
resp = d.get('job_response')
if resp:
    print(f\"Status: {job_st} | {resp}\")
else:
    print(f\"Status: {job_st} | {msg}\")
"
```

Repeat polling until `job_status` is one of: `completed`, `completed_with_warning`, `failed`, `cancelled`.

Do NOT invent fields -- `jobs status` returns ONLY `id`, `job_status`, `status_message`, `job_response`.

If the connection test succeeds, check the datasource state before you say it is ready for pipeline creation:

```bash
supaflow datasources get <NAME_OR_API_NAME> --json | python3 -c "
import sys,json; d=json.load(sys.stdin)
if 'error' in d: print(d['error']['message']); sys.exit(1)
print(f\"Datasource: {d.get('name')} | API name: {d.get('api_name')} | State: {d.get('state')}\")
"
```

**Hard gate for source datasources:**
- Do NOT say a datasource is ready for pipeline creation until its state is `active`.
- If the datasource will be used as a pipeline source, do NOT stop at connection test success. Source datasources also need a schema refresh before first pipeline creation so the object catalog is populated.

Once the datasource is `active`, run schema refresh for source use:

```bash
supaflow datasources refresh <NAME_OR_API_NAME> --json | python3 -c "
import sys,json; d=json.load(sys.stdin)
if 'error' in d: print(d['error']['message']); sys.exit(1)
print(f\"Refresh status: {d.get('status')} | Message: {d.get('message','')}\")
"
```

`datasources refresh` already waits for completion. If it fails because the datasource is not active yet, stop and tell the user to wait until the datasource reaches `active`, then rerun refresh.

**On success:** Tell the user one of these, depending on the role of the datasource:
- **Source datasource:** Connection test passed, datasource is `active`, and schema refresh completed. Mention the api_name and that it is ready for pipeline creation.
- **Destination datasource:** Connection test passed and datasource is `active`. Mention the api_name and that it is ready to be used as a project destination.

**On failure:** Proceed to Step 10.

## Step 10: Diagnose Failures

If the test job fails, get the full job details for diagnosis:

```bash
supaflow jobs get <JOB_ID> --json | python3 -c "
import sys,json; j=json.load(sys.stdin)
if 'error' in j: print(j['error']['message']); sys.exit(1)
print(f\"Status: {j['job_status']} | Duration: {j.get('execution_duration_ms',0)}ms\")
print(f\"Message: {j.get('status_message','')}\")
resp = j.get('job_response') or {}
print(f\"Objects: {resp.get('total_objects',0)} | Failed: {resp.get('total_failed',0)}\")
for o in j.get('object_details', []):
    name = o.get('fully_qualified_source_object_name','unknown')
    err = (o.get('ingestion_metrics') or {}).get('error_message','')
    print(f\"  {name}: ingestion={o.get('ingestion_status','?')} staging={o.get('staging_status','?')} loading={o.get('loading_status','?')}\")
    if err: print(f\"    Error: {err}\")
"
```

Also check logs for detailed error output:

```bash
supaflow jobs logs <JOB_ID> --json | python3 -c "
import sys,json; j=json.load(sys.stdin)
if 'error' in j: print(j['error']['message']); sys.exit(1)
print(f\"Status: {j.get('status','?')} | Message: {j.get('message','')}\")
"
```

Common failure causes and fixes:
- **Connection refused / timeout**: Verify host, port, firewall rules, VPN access
- **Authentication failed**: Wrong username/password or API credentials
- **Database not found**: Verify database name or schema
- **SSL error**: Check sslMode setting in the env file
- **API credential invalid**: OAuth token expired or client ID/secret wrong

After identifying the issue, guide the user to fix the env file and retry creation (Step 8).

---

## Guardrails Summary

- **MUST** read connector docs before checking existing datasources or asking for config (Step 2)
- **MUST** validate prerequisites from docs and confirm readiness before proceeding (Step 2)
- **MUST** run `datasources list` before asking for any credentials (Step 3)
- **MUST NOT** ask for passwords, secrets, tokens, private keys, or any `(sensitive)` field in chat
- **MUST NOT** dump full JSON responses -- always use `python3 -c` to extract only what is needed
- **MUST** show final confirmation summary and wait for explicit approval before `datasources create` (Step 8)
- When multiple same-type datasources exist, list all and ask -- NEVER assume which to use
