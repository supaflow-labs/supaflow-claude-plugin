---
description: Edit an existing Supaflow datasource configuration
allowed-tools: Bash(supaflow *), Read, Edit
argument-hint: [datasource-name]
---

# Edit Supaflow Datasource

You are helping the user edit an existing Supaflow datasource. Follow these steps exactly and in order.

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

## Step 2: Resolve the Datasource

If the user passed `[datasource-name]` as an argument, use that identifier. If no name was provided, list all datasources and ask the user which to edit.

```bash
supaflow datasources list --json | python3 -c "
import sys,json; d=json.load(sys.stdin)
if 'error' in d: print('ERROR: ' + d['error']['message']); sys.exit(1)
items = d.get('data', [])
if not items: print('No datasources found in this workspace.'); sys.exit(0)
print(f'Found {len(items)} datasource(s):')
for i, ds in enumerate(items, 1):
    print(f\"  {i}. {ds['name']} | connector={ds.get('connector_type','?')} | api_name={ds.get('api_name','?')} | state={ds.get('state','?')}\")
"
```

If multiple datasources exist with the same connector type, list all of them and ask which to edit. NEVER assume which one the user means.

Ask: "Which datasource would you like to edit? (provide the name or api_name)"

## Step 3: Get Current Configuration

Fetch the datasource's full configuration. Show non-sensitive fields to the user. For sensitive fields (objects containing an `fp` key -- the encrypted envelope), display `[encrypted]` instead of the raw value.

```bash
supaflow datasources get <NAME_OR_API_NAME> --json | python3 -c "
import sys,json; d=json.load(sys.stdin)
if 'error' in d: print('ERROR: ' + d['error']['message']); sys.exit(1)
print(f\"Name: {d.get('name')} | api_name: {d.get('api_name')} | connector: {d.get('connector_type')}\")
print(f\"State: {d.get('state')} | ID: {d.get('id')}\")
configs = d.get('configs') or {}
print('Current configuration:')
for k, v in configs.items():
    # Encrypted envelope: object with 'fp' key
    if isinstance(v, dict) and 'fp' in v:
        print(f\"  {k} = [encrypted]\")
    else:
        print(f\"  {k} = {v}\")
"
```

This shows all current configuration values with sensitive ones masked as `[encrypted]`. Encrypted envelopes have the shape `{ "v": 1, "fp": "...", "data": "..." }` -- they are safe to pass through unchanged when editing.

## Step 4: Ask What to Change

Present the current (masked) configuration to the user and ask:

"Here is the current configuration for `<name>`. What would you like to change?"

Wait for the user to specify which fields need updating. Common changes:
- Host, port, or database name
- Username
- Password or API secret (sensitive -- user edits file directly)
- Query mode or SSL settings
- OAuth credentials

## Step 5: Apply the Changes

### For non-sensitive changes (host, port, database, username, query mode, etc.)

Export the current config as an env file, then apply edits and submit:

```bash
# Export current config as env file (encrypted values preserved as enc: format)
supaflow datasources get <NAME_OR_API_NAME> --output current_<api_name>.env
```

Read the exported env file with the Read tool. Use the Edit tool to update only the fields that need to change. Do NOT modify encrypted `enc:` prefixed values unless replacing them.

Then submit:

```bash
supaflow datasources edit <NAME_OR_API_NAME> --from current_<api_name>.env --json | python3 -c "
import sys,json; d=json.load(sys.stdin)
if 'error' in d: print('ERROR: ' + d['error']['message']); sys.exit(1)
print(f\"Updated: {d.get('name')} (api_name={d.get('api_name')})\")
print(f\"State: {d.get('state')}\")
"
```

The edit command replaces the **entire** configs object. Always export first to preserve all unchanged fields.

### For sensitive changes (password, API secret, client secret, private key, token, etc.)

**NEVER ask for sensitive values in chat.**

Tell the user:

"To update sensitive fields, I'll export the current config to a file. Please open the file and update the sensitive field(s) directly, then let me know when done."

Export the current config:

```bash
supaflow datasources get <NAME_OR_API_NAME> --output current_<api_name>.env
```

Tell the user which sensitive fields to update:

"Please open `current_<api_name>.env` and update:
- `password` (replace the current `enc:...` value with your new password in plaintext -- the CLI will re-encrypt it automatically)

Type `done` when you have saved the file."

Wait for confirmation, then submit:

```bash
supaflow datasources edit <NAME_OR_API_NAME> --from current_<api_name>.env --json | python3 -c "
import sys,json; d=json.load(sys.stdin)
if 'error' in d: print('ERROR: ' + d['error']['message']); sys.exit(1)
print(f\"Updated: {d.get('name')} (api_name={d.get('api_name')})\")
print(f\"State: {d.get('state')}\")
"
```

The CLI auto-encrypts any plaintext value in the env file before submission. Unchanged `enc:` prefixed values are passed through without re-encryption.

## Step 6: Re-test the Connection (Optional)

After editing, offer to re-test the connection:

"Would you like to test the updated connection?"

If yes, run a connection test and poll for the result:

```bash
supaflow datasources test <NAME_OR_API_NAME> --json | python3 -c "
import sys,json; d=json.load(sys.stdin)
if 'error' in d: print('ERROR: ' + d['error']['message']); sys.exit(1)
print(f\"Test job started: {d.get('job_id','unknown')}\")
"
```

Poll job status until terminal state (`completed`, `completed_with_warning`, `failed`, `cancelled`):

```bash
supaflow jobs status <JOB_ID> --json | python3 -c "
import sys,json; d=json.load(sys.stdin)
if 'error' in d: print(d['error']['message']); sys.exit(1)
status = d['job_status']
msg = d.get('status_message') or ''
resp = d.get('job_response')
if resp:
    print(f\"Status: {status} | {resp}\")
else:
    print(f\"Status: {status} | {msg}\")
"
```

`jobs status` returns ONLY these 4 fields: `id`, `job_status`, `status_message`, `job_response`. Do NOT invent other fields.

If the test fails, use `jobs get <JOB_ID> --json` to get the full error details for diagnosis.

---

## Guardrails Summary

- **MUST NOT** ask for passwords, secrets, tokens, private keys, or any sensitive field in chat
- **MUST NOT** dump full JSON responses -- always use `python3 -c` to extract only what is needed
- When multiple same-type datasources exist, list all and ask -- NEVER assume which to edit
- When showing configs, always display `[encrypted]` for values that are objects with an `fp` key
- Always export the current config before editing to preserve all existing field values
