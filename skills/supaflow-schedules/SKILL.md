---
name: supaflow-schedules
description: This skill should be used when the user asks to "schedule a pipeline", "create a schedule", "set up cron", "automate sync", "recurring pipeline run", "edit schedule", "run schedule now", "view schedule history", "pause schedule", "resume schedule", "disable schedule", "enable schedule", "delete schedule", or mentions Supaflow schedules, cron expressions, pipeline automation, task scheduling, orchestration scheduling, or scheduled sync. Covers schedule lifecycle management in the @getsupaflow/cli.
---

# Supaflow Schedule Management

**AGENT BEHAVIOR:**
- **Execute all CLI commands directly via Bash.** Do NOT ask the user to run commands manually.
- **Preserve context window.** Pipe `--json` output through `python3 -c` to extract only the fields you need. NEVER dump full JSON into the conversation.
- **Only ask the user for:** schedule preferences (frequency, timezone).

Schedules trigger pipelines, tasks, or orchestrations on a cron-based recurring schedule. Each schedule targets exactly one resource and uses a standard 5-field cron expression executed in UTC.

All commands require prior authentication and workspace selection (see the supaflow-auth skill).

## Creating a Schedule

```bash
supaflow schedules create \
  --name "Hourly Sales Sync" \
  --pipeline <pipeline-identifier> \
  --cron "0 * * * *" \
  --timezone "America/New_York" \
  --description "Sync sales data every hour" \
  --json
```

Required flags:
- `--name`: Unique name within the workspace (also used as the identifier for schedule commands)
- `--cron`: Standard 5-field cron expression (minute, hour, day-of-month, month, day-of-week)
- **Exactly one** target flag (required):
  - `--pipeline <identifier>`: Target a pipeline (UUID or api_name)
  - `--task <identifier>`: Target a task (UUID or api_name)
  - `--orchestration <identifier>`: Target an orchestration (UUID or api_name)

Optional flags:
- `--timezone`: Display timezone (all execution is in UTC; timezone is display-only)
- `--description`: Human-readable description

Providing more than one target flag is an error.

## Cron Expression Reference

All schedules execute in UTC. The `--timezone` flag is for display purposes only.

| Pattern | Cron | Description |
|---------|------|-------------|
| Every hour | `0 * * * *` | At minute 0 of every hour |
| Every 6 hours | `0 */6 * * *` | At minute 0 every 6 hours |
| Every 15 minutes | `*/15 * * * *` | Every 15 minutes |
| Daily at midnight UTC | `0 0 * * *` | At 00:00 UTC |
| Daily at noon UTC | `0 12 * * *` | At 12:00 UTC |
| Weekdays at 9am UTC | `0 9 * * 1-5` | Mon-Fri at 09:00 UTC |
| Weekly on Sunday | `0 0 * * 0` | Sunday at 00:00 UTC |
| Monthly first day | `0 0 1 * *` | 1st of month at 00:00 UTC |

Cron field order: `minute hour day-of-month month day-of-week`

- minute: 0-59
- hour: 0-23
- day-of-month: 1-31
- month: 1-12
- day-of-week: 0-7 (0 and 7 are Sunday)
- Special: `*` (any), `*/N` (every N), `N-M` (range), `N,M` (list)

## Listing Schedules

```bash
# List all schedules
supaflow schedules list --json

# Filter by state
supaflow schedules list --state active --json
```

## Editing a Schedule

```bash
# Update cron expression
supaflow schedules edit <name> --cron "0 2 * * *" --json

# Update metadata
supaflow schedules edit <name> --name "New Name" --description "Updated description" --json

# Change display timezone
supaflow schedules edit <name> --timezone "UTC" --json

# Change target (pipeline, task, or orchestration -- provide exactly one)
supaflow schedules edit <name> --pipeline other_pipeline --json
supaflow schedules edit <name> --task my_task --json
supaflow schedules edit <name> --orchestration my_orch --json
```

Multiple flags can be combined in a single edit command.

## Manual Trigger

Trigger an immediate execution of a schedule (runs the associated target now):

```bash
supaflow schedules run <name> --json
```

This creates a job. Monitor with `supaflow jobs get <job-id> --json`.

## Execution History

View past executions of a schedule:

```bash
# Default history
supaflow schedules history <name> --json

# More entries
supaflow schedules history <name> --limit 20 --json
```

## State Management

Pause or resume a schedule without deleting it:

```bash
supaflow schedules disable <name> --json
supaflow schedules enable <name> --json
```

Disabled schedules do not trigger. Re-enabling resumes the cron schedule.

## Deletion

```bash
supaflow schedules delete <name> --json
```

## Identifier Resolution

Schedules resolve by **name** (not api_name), since schedule names are unique per workspace:

```bash
supaflow schedules edit "Hourly Sales Sync" --cron "0 */2 * * *" --json
```

This differs from datasources and pipelines, which resolve by api_name.

## Common Agent Patterns

### Create a schedule for an existing pipeline

```bash
supaflow schedules create \
  --name "Daily Analytics Sync" \
  --pipeline production_to_warehouse \
  --cron "0 2 * * *" \
  --timezone "America/New_York" \
  --json
```

### Check if a schedule exists before creating

```bash
supaflow schedules list --json
# Parse output to check for existing schedule name
```

### Pause all schedules during maintenance

```bash
# List all active schedules, then disable each:
supaflow schedules disable "Schedule Name" --json
```

### Review recent execution history for failures

```bash
supaflow schedules history "Hourly Sales Sync" --limit 10 --json
# Check job statuses in the response
```
