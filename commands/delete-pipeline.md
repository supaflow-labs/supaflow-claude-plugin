---
description: Delete a Supaflow pipeline permanently
allowed-tools: Bash(supaflow *)
argument-hint: [pipeline-name]
---

# Delete a Supaflow Pipeline

## Step 1: Setup Check

```bash
supaflow auth status --json | python3 -c "
import sys,json; d=json.load(sys.stdin)
if 'error' in d: print('ERROR: ' + d['error']['message']); sys.exit(1)
if not d.get('authenticated'): print('NOT AUTHENTICATED. Run: supaflow auth login'); sys.exit(1)
if not d.get('workspace_id'): print('NO WORKSPACE SELECTED. Run: supaflow workspaces select'); sys.exit(1)
print(f\"OK | workspace={d['workspace_name']} ({d['workspace_id']})\")
"
```

If exit code is non-zero: STOP. Tell the user exactly what failed. Do NOT proceed.

## Step 2: Identify the Pipeline

If a pipeline name was provided as an argument, use it directly. If not, list all pipelines and ask the user which to delete.

```bash
supaflow pipelines list --limit 200 --json | python3 -c "
import sys,json; d=json.load(sys.stdin)
if 'error' in d: print(d['error']['message']); sys.exit(1)
for p in d['data']:
    src = p['source']
    dst = p['destination']
    print(f\"{p['name']} | {src['name']} ({src['connector_name']}) -> {dst['name']} ({dst['connector_name']}) | api_name={p['api_name']} | state={p['state']}\")
total = d.get('total', len(d['data']))
if total > len(d['data']):
    print(f'WARNING: showing {len(d[\"data\"])} of {total} pipelines. Use --offset to page.')
"
```

Ask the user which pipeline to delete. Capture the `api_name`.

## Step 3: Show Pipeline Details

Fetch and display the pipeline's details so the user can confirm they have the right one.

```bash
supaflow pipelines get <pipeline-api-name> --json | python3 -c "
import sys,json; d=json.load(sys.stdin)
if 'error' in d: print(d['error']['message']); sys.exit(1)
c = d.get('configs', {})
print(f\"Name:            {d['name']}\")
print(f\"API name:        {d['api_name']}\")
print(f\"State:           {d['state']}\")
print(f\"Source:          {d.get('source',{}).get('name','?')} ({d.get('source',{}).get('connector_name','?')})\")
print(f\"Destination:     {d.get('destination',{}).get('name','?')} ({d.get('destination',{}).get('connector_name','?')})\")
print(f\"Pipeline prefix: {c.get('pipeline_prefix','?')}\")
"
```

Also show the number of selected objects:

```bash
supaflow pipelines schema list <pipeline-api-name> --json | python3 -c "
import sys,json; d=json.load(sys.stdin)
if 'error' in d: print(d['error']['message']); sys.exit(1)
selected = sum(1 for o in d['data'] if o['selected'])
print(f\"Selected objects: {selected}\")
"
```

## Step 4: Ask for Explicit Confirmation

Present a clear warning and ask for explicit confirmation. Do NOT proceed without it.

```
WARNING: This will permanently delete the pipeline "<name>".
- Source: <source name>
- Destination: <destination name>
- Pipeline prefix (destination schema): <prefix>
- Selected objects: <count>

This action cannot be undone. The destination data already written to <prefix> schema is NOT deleted -- only the pipeline configuration and sync state are removed.

Type YES to confirm deletion, or anything else to cancel.
```

Do NOT proceed unless the user responds with an explicit affirmative (yes, YES, y, confirm, etc.).

## Step 5: Delete the Pipeline

```bash
supaflow pipelines delete <pipeline-api-name> --yes --json | python3 -c "
import sys,json
raw = sys.stdin.read()
if raw.strip():
    d = json.loads(raw)
    if 'error' in d: print('ERROR: ' + d['error']['message']); sys.exit(1)
print('Pipeline deleted successfully.')
"
```

## Step 6: Verify Deletion

Confirm the pipeline no longer exists by fetching it directly (no pagination needed):

```bash
supaflow pipelines get <pipeline-api-name> --json | python3 -c "
import sys,json; d=json.load(sys.stdin)
if 'error' in d:
    code = d['error'].get('code', '')
    if code == 'NOT_FOUND':
        print('Confirmed: pipeline has been deleted.')
    else:
        print(f'ERROR: could not verify deletion ({code}): {d[\"error\"][\"message\"]}')
        sys.exit(1)
else:
    print(f'WARNING: Pipeline {d.get(\"api_name\",\"?\")} still exists (state={d.get(\"state\",\"?\")}).')
"
```
