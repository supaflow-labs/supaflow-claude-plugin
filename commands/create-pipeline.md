---
description: Create a new Supaflow pipeline from source to destination datasource
allowed-tools: Bash(supaflow *), Read, Edit, Write
argument-hint: [source-datasource] [destination-datasource]
---

# Create a Supaflow Pipeline

## Step 1: Setup Check

Run auth status first. If it fails, STOP immediately -- do not attempt to remediate.

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

## Step 2: Identify Source and Destination Datasources

```bash
supaflow datasources list --json | python3 -c "
import sys,json; d=json.load(sys.stdin)
if 'error' in d: print(d['error']['message']); sys.exit(1)
for ds in d['data']:
    print(f\"{ds['name']} | {ds['connector_type']} | api_name={ds['api_name']} | id={ds['id']} | state={ds['state']}\")
"
```

- If arguments were given (e.g., `source-datasource destination-datasource`), match by `name` or `api_name` from the list.
- If no arguments given, present the list and ask the user which datasource is the source and which is the destination.
- Capture both `api_name` and `id` for later steps. You need `id` for project matching and duplicate checks.

## Step 3: Find or Create a Project for the Destination

Projects link pipelines to a destination warehouse. Match by `warehouse_datasource_id` (NOT `warehouse_name`).

```bash
supaflow projects list --json | python3 -c "
import sys,json; d=json.load(sys.stdin)
if 'error' in d: print(d['error']['message']); sys.exit(1)
for p in d['data']:
    print(f\"{p['name']} | warehouse_id={p.get('warehouse_datasource_id','?')} | dest={p.get('warehouse_name','?')} ({p.get('warehouse_connector_name','?')}) | pipelines={p.get('pipeline_count',0)} | api_name={p['api_name']}\")
"
```

Compare each project's `warehouse_datasource_id` against the destination datasource's `id` from Step 2.

- If a project exists for that destination `id`: use it (capture `api_name`).
- If no project exists: create one.

```bash
supaflow projects create --name "<Destination Name> Project" --destination <destination-api-name> --json
```

Parse the create response to get the new project's `api_name`.

## Step 4: Check for Existing Pipelines (Duplicate Prevention)

**MANDATORY before creating.** Duplicate pipelines writing to the same destination schema cause data corruption.

```bash
supaflow pipelines list --json | python3 -c "
import sys,json; d=json.load(sys.stdin)
if 'error' in d: print(d['error']['message']); sys.exit(1)
for p in d['data']:
    src = p['source']
    dst = p['destination']
    proj = p.get('project', {})
    print(f\"{p['name']} | {src['name']} ({src['connector_name']}) -> {dst['name']} ({dst['connector_name']}) | api_name={p['api_name']} | state={p['state']} | src_id={src['datasource_id']} | dst_id={dst['datasource_id']} | project_id={proj.get('id','?')} | project_name={proj.get('name','?')}\")
"
```

**Parser contract -- use these nested fields ONLY:**
- `p['source']['name']`, `p['source']['datasource_id']`, `p['source']['connector_name']`
- `p['destination']['name']`, `p['destination']['datasource_id']`, `p['destination']['connector_name']`
- `p['project']['id']`, `p['project']['name']`
- NEVER use flat fields like `source_api_name`, `project_api_name`, or guessed names.
- NEVER print `source=?` or `project=?` -- if a field is missing, say it's missing explicitly.

Compare `src['datasource_id']` against the source `id` from Step 2, and `dst['datasource_id']` against the destination `id`.

**If a matching pipeline is found:**

Tell the user:
- The existing pipeline name, source, destination, and state.
- Show its currently selected objects:

```bash
supaflow pipelines schema list <existing-pipeline-api-name> --json | python3 -c "
import sys,json; d=json.load(sys.stdin)
if 'error' in d: print(d['error']['message']); sys.exit(1)
for o in d['data']:
    sel = 'SELECTED' if o['selected'] else 'excluded'
    print(f\"  {o['object']} | {sel} | {o['total_fields']} fields\")
"
```

Then ask the user:
1. Edit the existing pipeline's config?
2. Add objects to the existing pipeline?
3. Create a separate pipeline (REQUIRES explicit confirmation -- separate schema prefix means separate destination schema)?

If the user chooses option 3: warn clearly that a separate pipeline uses its own schema prefix and will write to a DIFFERENT destination schema. Ask for explicit confirmation before continuing.

## Step 5: Ask for Pipeline Name

Ask the user for a pipeline name. Suggest a default based on the source and destination (e.g., `sql_server_to_snowflake`), but let the user override. This name will be used with `--name` during create.

## Step 6: Generate Pipeline Config with `pipelines init`

**DO NOT manually construct pipeline config JSON.** Always use `pipelines init` to get capability-driven defaults.

```bash
supaflow pipelines init \
  --source <source-api-name> \
  --project <project-api-name> \
  --output /tmp/pipeline-config.json \
  --json
```

This creates `/tmp/pipeline-config.json` (the config) and `/tmp/pipeline-config-reference.txt` (field documentation).

## Step 7: Read and Present the ACTUAL Config Values

**STOP AND WAIT.** Read the generated file. Present ACTUAL values. NEVER manually derive defaults. NEVER say "auto-generated prefix" without showing the actual value.

```bash
python3 -c "
import json
c = json.load(open('/tmp/pipeline-config.json'))
print(f\"Pipeline prefix:      {c['pipeline_prefix']}  ** CANNOT be changed after creation **\")
print(f\"Ingestion mode:       {c['ingestion_mode']}\")
print(f\"Load mode:            {c['load_mode']}\")
print(f\"Schema evolution:     {c['schema_evolution_mode']}\")
print(f\"Hard deletes:         {c['perform_hard_deletes']}\")
print(f\"Full sync frequency:  {c.get('full_sync_frequency', 'not set')}\")
print(f\"Error handling:       {c.get('error_handling', 'not set')}\")
"
```

Present to the user:

```
Before I create the pipeline, please review these settings:

Pipeline prefix:     <actual value>  ** CANNOT be changed after creation **
Ingestion mode:      <actual value>
Load mode:           <actual value>
Schema evolution:    <actual value>
Hard deletes:        <actual value>

To see all valid options for each field, check /tmp/pipeline-config-reference.txt.
Want to change any of these, or shall I proceed?
```

**DO NOT call `pipelines create` until the user explicitly confirms or provides changes.**

## Step 8: Apply User Changes (if any) and Get Final Confirmation

If the user requests changes, edit the generated file. Do NOT rewrite it from scratch -- edit only the fields that change.

```bash
python3 -c "
import json
c = json.load(open('/tmp/pipeline-config.json'))
c['pipeline_prefix'] = 'my_custom_prefix'
c['is_custom_prefix'] = True
# Apply any other requested changes here
json.dump(c, open('/tmp/pipeline-config.json', 'w'), indent=2)
"
```

After any edit, re-read the file and show ALL final values. Ask for explicit final confirmation.

```bash
python3 -c "
import json
c = json.load(open('/tmp/pipeline-config.json'))
print('Final pipeline config:')
print(f\"  Pipeline prefix:      {c['pipeline_prefix']}  ** CANNOT be changed after creation **\")
print(f\"  Ingestion mode:       {c['ingestion_mode']}\")
print(f\"  Load mode:            {c['load_mode']}\")
print(f\"  Schema evolution:     {c['schema_evolution_mode']}\")
print(f\"  Hard deletes:         {c['perform_hard_deletes']}\")
print(f\"  Full sync frequency:  {c.get('full_sync_frequency', 'not set')}\")
print(f\"  Error handling:       {c.get('error_handling', 'not set')}\")
"
```

Ask: "This is the final config. Proceed with pipeline creation?" Only continue after explicit yes.

**NEVER treat a partial edit request as blanket approval to create.** Every change requires re-displaying all final values and a new explicit confirmation.

## Step 9: Prepare Object Selections (Optional)

If the user wants to select specific objects (not all discovered), create an objects file.
First, browse available objects:

```bash
supaflow datasources catalog <SOURCE_DATASOURCE_NAME> --json | python3 -c "
import sys,json; d=json.load(sys.stdin)
for obj in d.get('data', []):
    print(obj['fully_qualified_name'])
"
```

Ask the user which objects to include. Then create a selection file using the `fully_qualified_name` from the catalog:

```bash
python3 -c "
import json
# Each entry MUST have: fully_qualified_name (string), selected (boolean), fields (null = all fields)
objects = [
    {'fully_qualified_name': 'dbo.customers', 'selected': True, 'fields': None},
    {'fully_qualified_name': 'dbo.orders', 'selected': True, 'fields': None}
]
json.dump(objects, open('/tmp/pipeline-objects.json', 'w'), indent=2)
"
```

**Object file contract:** The CLI expects an array of `{ fully_qualified_name, selected, fields }`. Use `fully_qualified_name` (NOT `object` or `name`). Set `fields: null` to select all fields for that object.

If the user wants all objects, skip this step (omitting `--objects` selects all discovered objects by default).

## Step 10: Create the Pipeline

The CLI requires `--name`, `--source`, and `--project`. Use `--config` for config overrides and `--objects` for object selections.

```bash
supaflow pipelines create \
  --name "<PIPELINE_NAME>" \
  --source <SOURCE_DATASOURCE_API_NAME> \
  --project <PROJECT_API_NAME> \
  --config /tmp/pipeline-config.json \
  --objects /tmp/pipeline-objects.json \
  --json | python3 -c "
import sys,json; d=json.load(sys.stdin)
if 'error' in d: print('ERROR: ' + d['error']['message']); sys.exit(1)
print(f\"Created: {d['name']} | api_name={d['api_name']} | id={d['id']} | state={d['state']}\")
print(f\"Pipeline prefix: {d.get('pipeline_prefix', 'NOT FOUND')}\")
print(f\"Objects selected: {d.get('objects_selected', '?')}\")
"
```

If no `--objects` file was created (user wants all objects), omit `--objects`:

```bash
supaflow pipelines create \
  --name "<PIPELINE_NAME>" \
  --source <SOURCE_DATASOURCE_API_NAME> \
  --project <PROJECT_API_NAME> \
  --config /tmp/pipeline-config.json \
  --json | python3 -c "
import sys,json; d=json.load(sys.stdin)
if 'error' in d: print('ERROR: ' + d['error']['message']); sys.exit(1)
print(f\"Created: {d['name']} | api_name={d['api_name']} | id={d['id']} | state={d['state']}\")
print(f\"Pipeline prefix: {d.get('pipeline_prefix', 'NOT FOUND')}\")
print(f\"Objects selected: {d.get('objects_selected', '?')}\")
"
```

Verify the response includes `pipeline_prefix` at the top level. If it is missing, warn the user.

### Duplicate Constraint Handling

If `pipelines create` fails with a duplicate or unique constraint error:

**STOP immediately.** Show the error message verbatim. Ask the user:
- Use a different pipeline name?
- Use a different pipeline prefix?
- Cancel?

**NEVER silently rename the pipeline. NEVER auto-increment the name or prefix (e.g., do NOT try `salesforce_2` automatically). Wait for explicit user direction.**

## Step 11: Verify Selected Objects

After creation, verify the actual selected objects. Do NOT trust the create response summary alone.

```bash
supaflow pipelines schema list <pipeline-api-name> --json | python3 -c "
import sys,json; d=json.load(sys.stdin)
if 'error' in d: print(d['error']['message']); sys.exit(1)
selected = [o for o in d['data'] if o['selected']]
excluded = [o for o in d['data'] if not o['selected']]
print(f\"Selected: {len(selected)} objects\")
for o in selected:
    print(f\"  {o['object']} | {o['total_fields']} fields\")
if excluded:
    print(f\"Excluded: {len(excluded)} objects\")
"
```

**Field name contract:** `pipelines schema list` uses `object` for the object name. NOT `fully_qualified_name`. NOT `name`. Use `o['object']` only.

Report the final list to the user and confirm the pipeline is ready.
