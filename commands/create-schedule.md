---
description: Create a recurring schedule for a Supaflow pipeline
allowed-tools: Bash(supaflow *)
argument-hint: [pipeline-name]
---

# Create a Supaflow Schedule

## Setup Check

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

## Step 1: Identify Pipeline

If a pipeline name was provided as an argument, use it. If not, list available pipelines and ask the user which one to schedule.

```bash
supaflow pipelines list --json | python3 -c "
import sys,json; d=json.load(sys.stdin)
if 'error' in d: print(d['error']['message']); sys.exit(1)
for p in d['data']:
    src = p['source']
    dst = p['destination']
    print(f\"{p['name']} | {src['name']} ({src['connector_name']}) -> {dst['name']} ({dst['connector_name']}) | api_name={p['api_name']} | state={p['state']}\")
"
```

Match the user's argument against `name` or `api_name` from the list. Capture BOTH the pipeline's `api_name` (for `--pipeline` flag) and `id` (UUID, for matching against `target_id` in schedules). If no argument was given, present the list and ask which pipeline to schedule.

To get the pipeline UUID:
```bash
supaflow pipelines list --json | python3 -c "
import sys,json; d=json.load(sys.stdin)
for p in d['data']:
    if p['api_name'] == '<PIPELINE_API_NAME>' or p['name'] == '<PIPELINE_NAME>':
        print(f\"id={p['id']} api_name={p['api_name']}\")
"
```

## Step 2: Check Existing Schedules

Before asking for any schedule details, check whether schedules already exist for this pipeline.

```bash
supaflow schedules list --json | python3 -c "
import sys,json; d=json.load(sys.stdin)
if 'error' in d: print(d['error']['message']); sys.exit(1)
for s in d['data']:
    print(f\"{s['name']} | {s['cron_schedule']} | target={s.get('target_type','?')}:{s.get('target_id','?')} | state={s['state']}\")
"
```

Filter the output to find any schedule whose `target_id` matches the selected pipeline. If a schedule for this pipeline already exists:

Tell the user the existing schedule name, cron expression, and state. Then ask:
1. Edit the existing schedule?
2. Create an additional schedule for the same pipeline?
3. Cancel -- do nothing?

Wait for the user's choice before continuing. Do NOT proceed to Step 3 until the user responds.

## Step 3: Ask for Schedule Details

Ask for schedule details ONE question at a time. Do NOT present all questions at once.

**Question 1 -- Frequency:**

Ask: "How often should this pipeline run? Here are common patterns:"

```
every hour          ->  0 * * * *
every 6 hours       ->  0 */6 * * *
daily at 2am UTC    ->  0 2 * * *
weekdays at 9am UTC ->  0 9 * * 1-5
```

"You can also enter a custom cron expression."

Wait for the user's answer. Capture the cron expression.

**Question 2 -- Timezone:**

Ask: "What timezone should the schedule use? (Press Enter to use UTC, or specify a timezone like `America/New_York` or `Europe/London`.)"

Wait for the user's answer. Default to `UTC` if the user presses Enter or says "UTC" or "default".

**Question 3 -- Schedule Name:**

Ask: "What should this schedule be called? (Press Enter to use the suggested default: `<pipeline_api_name>_<frequency_hint>` where frequency_hint is `hourly`, `daily`, etc. based on the cron expression.)"

Wait for the user's answer. If the user presses Enter, use the suggested default name.

## Step 4: Confirm and Create

Show a confirmation summary and wait for explicit yes before creating.

```
Schedule:   <SCHEDULE_NAME>
Pipeline:   <PIPELINE_NAME>
Cron:       <CRON_EXPRESSION> (<TIMEZONE>)
Timezone:   <TIMEZONE>

Create this schedule?
```

Do NOT call `schedules create` until the user explicitly confirms with "yes" or equivalent.

Once confirmed, run:

```bash
supaflow schedules create \
  --name "<SCHEDULE_NAME>" \
  --pipeline <PIPELINE_API_NAME> \
  --cron "<CRON_EXPRESSION>" \
  --timezone "<TIMEZONE>" \
  --json | python3 -c "
import sys,json; d=json.load(sys.stdin)
if 'error' in d: print('ERROR: ' + d['error']['message']); sys.exit(1)
print(f\"Created schedule: {d['name']} | cron: {d['cron']} | state: {d['state']}\")
"
```

If the command fails, show the error verbatim. Do NOT retry automatically. Ask the user how to proceed.

## Step 5: Verify

After creation, confirm the new schedule appears in the list.

```bash
supaflow schedules list --json | python3 -c "
import sys,json; d=json.load(sys.stdin)
if 'error' in d: print(d['error']['message']); sys.exit(1)
for s in d['data']:
    print(f\"{s['name']} | {s['cron_schedule']} | target={s.get('target_type','?')}:{s.get('target_id','?')} | state={s['state']}\")
"
```

Confirm the new schedule name appears in the output with the correct `cron_schedule` field. Report the result to the user.
