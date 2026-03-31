---
description: Edit an existing Supaflow pipeline configuration or object selection
allowed-tools: Bash(supaflow *), Read, Edit, Write
argument-hint: [pipeline-name]
---

# Edit a Supaflow Pipeline

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

If a pipeline name was provided as an argument, use it directly. If not, list all pipelines and ask the user which to edit.

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

**Parser contract:** Use nested fields only:
- `p['source']['name']`, `p['source']['connector_name']`
- `p['destination']['name']`, `p['destination']['connector_name']`
- `p['api_name']`, `p['state']`

Ask the user which pipeline to edit. Capture the `api_name` for subsequent steps.

## Step 3: Show Current Pipeline Config

Fetch the current configuration and present a summary to the user.

```bash
supaflow pipelines get <pipeline-api-name> --json | python3 -c "
import sys,json; d=json.load(sys.stdin)
if 'error' in d: print(d['error']['message']); sys.exit(1)
c = d.get('configs', {})
print(f\"Name:               {d['name']}\")
print(f\"State:              {d['state']}\")
print(f\"Pipeline prefix:    {c.get('pipeline_prefix','?')}  (cannot be changed)\")
print(f\"Ingestion mode:     {c.get('ingestion_mode','?')}\")
print(f\"Load mode:          {c.get('load_mode','?')}\")
print(f\"Schema evolution:   {c.get('schema_evolution_mode','?')}\")
print(f\"Hard deletes:       {c.get('perform_hard_deletes','?')}\")
print(f\"Full sync freq:     {c.get('full_sync_frequency','?')}\")
print(f\"Error handling:     {c.get('error_handling','?')}\")
"
```

## Step 4: Ask What to Change

Ask the user what they want to change:
1. Pipeline configuration (ingestion mode, load mode, schema evolution, etc.)
2. Object selection (add or remove objects from the sync)

Handle both in sequence if the user wants to change both.

## Step 5a: Edit Pipeline Config

For configuration changes, use `pipelines edit` with the `--config` flag. First export the current config, apply changes, then submit.

Get the current config into a file:

```bash
supaflow pipelines get <pipeline-api-name> --json | python3 -c "
import sys,json; d=json.load(sys.stdin)
if 'error' in d: print(d['error']['message']); sys.exit(1)
json.dump(d.get('configs', {}), open('/tmp/pipeline-edit-config.json', 'w'), indent=2)
print('Config exported to /tmp/pipeline-edit-config.json')
"
```

Apply the requested changes (do NOT rewrite the file from scratch -- edit only the changed fields):

```bash
python3 -c "
import json
c = json.load(open('/tmp/pipeline-edit-config.json'))
# Apply requested changes, for example:
c['load_mode'] = 'TRUNCATE_AND_LOAD'
c['schema_evolution_mode'] = 'BLOCK_ALL'
json.dump(c, open('/tmp/pipeline-edit-config.json', 'w'), indent=2)
"
```

Show the user the final values and ask for confirmation before submitting:

```bash
python3 -c "
import json
c = json.load(open('/tmp/pipeline-edit-config.json'))
print('Updated config:')
print(f\"  Ingestion mode:     {c.get('ingestion_mode','?')}\")
print(f\"  Load mode:          {c.get('load_mode','?')}\")
print(f\"  Schema evolution:   {c.get('schema_evolution_mode','?')}\")
print(f\"  Hard deletes:       {c.get('perform_hard_deletes','?')}\")
print(f\"  Full sync freq:     {c.get('full_sync_frequency','?')}\")
"
```

Submit after confirmation:

```bash
supaflow pipelines edit <pipeline-api-name> --config /tmp/pipeline-edit-config.json --json | python3 -c "
import sys,json; d=json.load(sys.stdin)
if 'error' in d: print('ERROR: ' + d['error']['message']); sys.exit(1)
print(f\"Updated: {d['name']} | state={d['state']}\")
"
```

Other edit flags (can be combined in a single command):

```bash
# Update name
supaflow pipelines edit <pipeline-api-name> --name "New Pipeline Name" --json

# Update description
supaflow pipelines edit <pipeline-api-name> --description "Updated description" --json

# Combine flags
supaflow pipelines edit <pipeline-api-name> --name "New Name" --description "New description" --json
```

## Step 5b: Edit Object Selection

First, list the current selected objects.

```bash
supaflow pipelines schema list <pipeline-api-name> --all --json | python3 -c "
import sys,json; objs=json.load(sys.stdin)
if isinstance(objs, dict) and 'error' in objs: print(objs['error']['message']); sys.exit(1)
for o in objs:
    sel = 'SELECTED' if o['selected'] else 'excluded'
    print(f\"  {o['fully_qualified_name']} | {sel}\")
"
```

**Field name contract:** `schema list --json` returns a raw array. Each item uses `fully_qualified_name`.

### Adding a Single Object

Use `schema add` directly -- no file export needed:

```bash
supaflow pipelines schema add <pipeline-api-name> <OBJECT_NAME> --json | python3 -c "
import sys,json; d=json.load(sys.stdin)
if 'error' in d: print('ERROR: ' + d['error']['message']); sys.exit(1)
print('Object added successfully')
"
```

### Bulk Object Selection

For multiple changes, export current selections, edit, then reimport:

```bash
# Export current selections to a file (raw array with fully_qualified_name)
supaflow pipelines schema list <pipeline-api-name> --all --json > /tmp/objects.json

# Read and show current state
python3 -c "
import json
objs = json.load(open('/tmp/objects.json'))
print(f'Total objects: {len(objs)}')
for o in objs:
    state = 'SELECTED' if o['selected'] else 'excluded'
    print(f\"  {o['fully_qualified_name']} | {state}\")
"
```

Edit selections:

```bash
python3 -c "
import json
objs = json.load(open('/tmp/objects.json'))
# Enable objects
for o in objs:
    if o['fully_qualified_name'] in ['public.orders', 'public.customers']:
        o['selected'] = True
# Disable objects
for o in objs:
    if 'internal' in o['fully_qualified_name']:
        o['selected'] = False
json.dump(objs, open('/tmp/objects.json', 'w'), indent=2)
print('Updated.')
"
```

Apply the new selection:

```bash
supaflow pipelines schema select <pipeline-api-name> --from /tmp/objects.json --json | python3 -c "
import sys,json; d=json.load(sys.stdin)
if isinstance(d, dict) and 'error' in d: print('ERROR: ' + d['error']['message']); sys.exit(1)
if isinstance(d, list): d = d[0]
if d.get('error_count', 0) > 0:
    print(f\"PARTIAL FAILURE: {d['error_count']} of {d['processed_count']} objects failed\")
    for e in (d.get('error_messages') or []):
        print(f\"  {e['fully_qualified_name']}: {e['message']}\")
    sys.exit(1)
print(f\"Updated: {d['processed_count']} objects processed, {d.get('updated_count',0)} updated\")
"
```

## Step 6: Show Final State

After all edits, show the final pipeline state to confirm everything looks correct.

```bash
supaflow pipelines get <pipeline-api-name> --json | python3 -c "
import sys,json; d=json.load(sys.stdin)
if 'error' in d: print(d['error']['message']); sys.exit(1)
c = d.get('configs', {})
print(f\"Pipeline: {d['name']} ({d['api_name']})\")
print(f\"State: {d['state']}\")
print(f\"Ingestion mode:   {c.get('ingestion_mode','?')}\")
print(f\"Load mode:        {c.get('load_mode','?')}\")
print(f\"Schema evolution: {c.get('schema_evolution_mode','?')}\")
"

supaflow pipelines schema list <pipeline-api-name> --json | python3 -c "
import sys,json; objs=json.load(sys.stdin)
if isinstance(objs, dict) and 'error' in objs: print(objs['error']['message']); sys.exit(1)
selected = [o for o in objs if o['selected']]
print(f'Selected objects: {len(selected)}')
for o in selected:
    print(f\"  {o['fully_qualified_name']}\")
"
```
