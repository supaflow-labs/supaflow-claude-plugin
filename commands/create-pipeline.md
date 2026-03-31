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
supaflow pipelines schema list <existing-pipeline-api-name> --all --json | python3 -c "
import sys,json; objs=json.load(sys.stdin)
if isinstance(objs, dict) and 'error' in objs: print(objs['error']['message']); sys.exit(1)
selected = [o for o in objs if o['selected']]
excluded = [o for o in objs if not o['selected']]
print(f'Selected: {len(selected)} objects')
for o in selected:
    print(f\"  {o['fully_qualified_name']}\")
if excluded:
    print(f'Excluded: {len(excluded)} objects')
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

**Typo check on custom prefix:** If the user provides a custom `pipeline_prefix` that looks like a misspelling of the source connector name or datasource name (e.g., `googel` vs `google`, `salseforce` vs `salesforce`), flag it before confirming: "The prefix you entered is `<value>` -- did you mean `<corrected>`? This cannot be changed after creation." The prefix is permanent, so catching typos here prevents a permanent mistake.

## Step 9: Object Scope (REQUIRED)

Object scope is a required decision. Do NOT silently default to all objects.

Ask the user: "Do you want to sync **all discovered objects**, or do you want to **choose a subset**?"

Wait for the user's answer before proceeding.

### Path A: All Objects

If the user explicitly says "all objects" (or equivalent):
- State clearly: "The pipeline will include all discovered objects. The `--objects` flag will be omitted, which selects everything from the source catalog."
- Include this in the final confirmation summary (Step 10).
- Do NOT pass `--objects` to `pipelines create`.

### Path B: Choose Subset

If the user wants to select specific objects:

1. Export the catalog directly to the objects file. The CLI writes the correct `{ fully_qualified_name, selected, fields }` shape with all objects selected by default:
```bash
supaflow datasources catalog <SOURCE_DATASOURCE_NAME> --output /tmp/pipeline-objects.json --json
```

2. Show the exported objects:
```bash
python3 -c "
import json
with open('/tmp/pipeline-objects.json') as f:
    objs = json.load(f)
for o in objs:
    print(o['fully_qualified_name'])
print(f'Total: {len(objs)} objects')
"
```

3. Ask the user: **"Which objects do you want to include?"** Frame this as an INCLUDE question, not an exclude question. The user's answer is the list of objects to keep.

**IMPORTANT: When the user says "just X and Y", that means INCLUDE only X and Y. It does NOT mean exclude X and Y. This is the most common misinterpretation -- get it right.**

4. Edit the file in place -- set `selected: false` for everything EXCEPT the user's chosen objects. Do NOT rewrite the file from scratch:
```bash
python3 -c "
import json
with open('/tmp/pipeline-objects.json') as f:
    objs = json.load(f)
include = ['dbo.customers', 'dbo.orders']  # objects the user wants to INCLUDE
for o in objs:
    o['selected'] = o['fully_qualified_name'] in include
with open('/tmp/pipeline-objects.json', 'w') as f:
    json.dump(objs, f, indent=2)
selected = sum(1 for o in objs if o['selected'])
print(f'Selected: {selected}/{len(objs)} objects')
"
```

5. Pass `--objects /tmp/pipeline-objects.json` to `pipelines create`.

## Step 10: Create the Pipeline

The CLI requires `--name`, `--source`, and `--project`. Use `--config` for config overrides and `--objects` for object selections.

Before creating, present the final confirmation summary including the object scope decision from Step 9:

```
Final confirmation:

Pipeline name:      <PIPELINE_NAME>
Source:             <SOURCE_DATASOURCE_API_NAME>
Project:            <PROJECT_API_NAME>
Pipeline prefix:    <actual value>  ** CANNOT be changed after creation **
Ingestion mode:     <actual value>
Load mode:          <actual value>
Schema evolution:   <actual value>
Hard deletes:       <actual value>
Object scope:       all discovered objects (--objects omitted)
```

or if a subset was chosen:

```
Object scope:       <N> objects selected (via --objects file)
```

Ask: **"Proceed with pipeline creation?"** Wait for explicit yes. The object scope decision alone is NOT approval to create. This is the final gate.

### Path B: Create with selected objects

If the user chose a subset (Step 9 Path B), pass `--objects`:

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

### Path A: Create with all objects

If the user chose all objects (Step 9 Path A), omit `--objects`:

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
supaflow pipelines schema list <pipeline-api-name> --all --json | python3 -c "
import sys,json; objs=json.load(sys.stdin)
if isinstance(objs, dict) and 'error' in objs: print(objs['error']['message']); sys.exit(1)
selected = [o for o in objs if o['selected']]
excluded = [o for o in objs if not o['selected']]
print(f'Selected: {len(selected)} objects')
for o in selected:
    print(f\"  {o['fully_qualified_name']}\")
if excluded:
    print(f'Excluded: {len(excluded)} objects')
"
```

**Field name contract:** `pipelines schema list --json` returns a raw array. Each item uses `fully_qualified_name` (same field name as `datasources catalog --output` and `schema select --from`).

Report the final list to the user.

Pipeline is ready. To sync now, use `/sync-pipeline`. To set up recurring syncs, use `/create-schedule`.
