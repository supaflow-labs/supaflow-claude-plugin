---
name: using-supaflow
description: Supaflow CLI command-first workflow for pipelines, syncs, and jobs
---

# Supaflow Plugin

You have the Supaflow plugin installed. It provides commands for managing datasources, pipelines, jobs, and schedules via the Supaflow CLI.

<EXTREMELY-IMPORTANT>
If you think there is even a 1% chance a Supaflow command applies to what the user is asking, you ABSOLUTELY MUST use that command.

IF A COMMAND COVERS THE TASK, YOU DO NOT HAVE A CHOICE. YOU MUST USE IT.

This is not negotiable. This is not optional. You cannot rationalize your way out of this by saying the task is simple, exploratory, or just needs one quick check.
</EXTREMELY-IMPORTANT>

## Instruction Priority

Supaflow skills and commands override default assistant behavior, but user instructions always take precedence:

1. **User instructions** (`AGENTS.md`, direct requests, repo conventions) -- highest priority
2. **Supaflow skills and commands** -- override default assistant behavior where they conflict
3. **Default system behavior** -- lowest priority

If the user explicitly asks you not to use a command, follow the user. Otherwise, use the command.

## Using Supaflow Commands and Skills

## The Rule

**Invoke the relevant Supaflow command BEFORE any response or action.** This includes clarifying questions. If a command exists for the task, start there rather than improvising the workflow in chat.

If no command exists, use the relevant Supaflow reference skill for domain knowledge and keep the workflow lightweight and explicit.

## HARD RULES

These rules are non-negotiable. Violating any of them is a bug.

1. **Use commands when they exist.** If a command covers the user's request, invoke it. Do not recreate the same workflow freehand in chat.
2. **Ask one question at a time.** Never batch multiple blocking questions into one message.
3. **Do not infer approval from a partial answer.** If the user changes one field, that is not approval for the rest.
4. **Do not create before explicit confirmation.** Pipelines, datasources, schedules: show the user what you are about to create and wait for explicit approval.
5. **Do not guess CLI output fields.** Use only documented field names. If you are unsure, run the command with `--json` and inspect the actual output shape.
6. **Do not ask for passwords or secrets in chat.** Tell the user to edit the env file directly.
7. **Stop on errors.** If a create/edit command fails, show the error verbatim and ask the user what to do. Never silently retry, rename, auto-increment, or "fix" the input without approval.
8. **Always run `pipelines init` before `pipelines create`.** Present actual config values from the generated file and wait for explicit confirmation.
9. **Object scope is a required decision.** Ask whether to sync all objects or a subset. Only omit `--objects` after the user explicitly says to sync all discovered objects.
10. **Parse JSON with `python3 -c`.** Never dump full JSON output into the conversation.
11. **In shell loops, never use `status` as a variable name** (read-only in zsh). Use `job_status` or `poll_status`.

## Red Flags

These thoughts mean STOP. You are rationalizing your way out of the command-first workflow.

| Thought | Reality |
|---|---|
| "This is just a simple pipeline setup" | Simple Supaflow tasks still need the command guardrails. |
| "I need to ask a few questions first" | If a command exists, use it before freeform clarifying. |
| "Let me inspect the CLI output quickly from memory" | Run the command with `--json` and inspect the real shape. |
| "I can probably use the defaults" | Use `pipelines init`, read the generated file, and show actual values. |
| "The user only changed one field, so the rest is fine" | Partial edits are not approval. Re-show the full final config. |
| "I can retry with a different name/prefix" | Silent retries are a bug. Stop and ask. |
| "I already know the job fields" | The CLI contract is the source of truth, not memory. |
| "This doesn't need a command" | If a command exists, use it. |
| "I'll just sync all objects by default" | Object scope is a required question. Ask first. |
| "I can trigger the sync with a quick CLI call" | Use /sync-pipeline. It has the correct response parser and polling contract. |

## Conversation Discipline

These rules apply to every Supaflow workflow:

1. Ask one question at a time.
2. Ask only the next blocking question. Do not combine datasource choice, object selection, config approval, and duplicate-handling into one message.
3. After each user answer, update your understanding and ask only the next blocking question.
4. If the user gives a partial answer, do not infer approval for the remaining fields.
5. When a command requires confirmation, present the actual values and wait.
6. If the command fails, show the error and ask what the user wants to do next.

## Available Commands

Use these commands for the corresponding user intents. Commands have tool restrictions and embedded guardrails that prevent common mistakes.

| User wants to... | Command |
|---|---|
| Create a new datasource / connect to a database | `/create-datasource` |
| Edit datasource config or credentials | `/edit-datasource` |
| Create a new pipeline / sync data | `/create-pipeline` |
| Edit pipeline config or object selection | `/edit-pipeline` |
| Delete a pipeline | `/delete-pipeline` |
| Check job status or latest sync | `/check-job` |
| Diagnose a failed job | `/explain-job-failure` |
| Sync a pipeline / run a sync | `/sync-pipeline` |
| Schedule a pipeline | `/create-schedule` |

If the user's request spans multiple commands (e.g., "build a pipeline", "set up a pipeline from scratch"), **start with `/create-pipeline`** -- it checks for existing datasources and only needs `/create-datasource` if something is missing:

1. `/create-pipeline` -- this is the primary entrypoint. It lists existing datasources, checks for duplicates, and handles project resolution. Only if a required source or destination datasource is missing, branch to step 2.
2. `/create-datasource` -- only if `/create-pipeline` identified a missing datasource. Then return to `/create-pipeline`.
3. `/sync-pipeline` -- to trigger the first sync and verify data.
4. `/create-schedule` -- if the user wants recurring syncs.

**Do NOT start with `/create-datasource` when the user asks to "build a pipeline."** The user's intent is pipeline creation, not datasource creation. `/create-pipeline` handles datasource discovery internally.

## Before Any Supaflow Operation

Every command starts with an auth check. If the CLI is not authenticated or no workspace is selected, stop and tell the user how to fix it:
- Not installed: `npm install -g @getsupaflow/cli`
- Not authenticated: `supaflow auth login` (user needs API key from https://app.supa-flow.io > Settings > API Keys)
- No workspace: `supaflow workspaces select <name>`

Do not try to repair setup from inside a restricted command if the command does not have the tools to do so. Explain the blocker and stop.

## Parser Contracts

These are the correct JSON field names for each CLI output. Never invent alternatives.

**`jobs status --json`:** `id`, `job_status`, `status_message`, `job_response`
- NEVER use: `phase`, `duration`, `completed_at`, `progress`

**`jobs get --json`:** `execution_duration_ms`, `ended_at`, `job_response`, `object_details`
- NEVER use: `duration`, `completed_at`, `objects`, `rows_read`

**`pipelines list --json` / `datasources list --json`:** wraps results in `{ "data": [...], "total": N, "limit": N, "offset": N }`
- Default limit is 25. **Always use `--limit 200`** to avoid silently missing items. The CLI hard-caps at 200.
- Always check `total > len(data)` and warn the user about truncation.
- **For exhaustive scans** (duplicate checks, deletion verification): page with `--offset` until `len(batch) < limit`. A single page is NOT authoritative.
- **For single-item lookups**: prefer `pipelines get <identifier>` or `datasources get <identifier>` which resolve directly without pagination.
- Pipeline items use nested fields: `source.name`, `source.datasource_id`, `destination.name`, `destination.datasource_id`, `project.id`, `project.name`
- NEVER use flat fields like `source_name` or `project_api_name`

**`pipelines schema list --json`:** returns a raw JSON array (NOT wrapped in `{ data: [...] }`). Each item uses `fully_qualified_name`, `selected`, `fields`
- This is the same shape consumed by `pipelines schema select --from`
- NEVER use `object` or `name` (old contract, removed)

**`projects list --json`:** match destination by `warehouse_datasource_id`, not `warehouse_name`

**`datasources catalog --json`:** use `fully_qualified_name`
- Use `--output <file>` and parse locally. Never dump catalog into conversation.

**`schedules list --json`:** use `cron_schedule` (not `cron`), `target_type`, `target_id` (not `target_name`)

## CLI Reference

For JSON output contracts, global flags, identifier resolution, auth environment variables, and error codes, read `cli-reference.md` in this skill's directory.

## Domain Skills (Reference Only)

These skills contain background knowledge. Use them when you need connector details, pipeline configuration context, or job metrics. They are reference material only. Do NOT use them to replace a command-backed workflow:

- `supaflow-datasources` -- connectors, credentials, and catalog
- `supaflow-pipelines` -- pipeline setup, schema, and sync modes
- `supaflow-jobs` -- look up job status, metrics, or logs
- `supaflow-schedules` -- cron schedules and timezone handling
