---
name: using-supaflow
description: Supaflow MCP/CLI workflow gate for pipelines, syncs, jobs, datasources, and schedules
---

# Supaflow Plugin

You have the Supaflow plugin installed. It provides deterministic workflows for managing datasources, pipelines, jobs, and schedules. In Claude Desktop, the authoritative execution surface is the host-side Supaflow MCP server. In terminal Claude Code, the fallback execution surface is the Supaflow CLI slash-command workflow.

<EXTREMELY-IMPORTANT>
If `mcp__supaflow__auth_status` is available, you ABSOLUTELY MUST use the Supaflow MCP path for Supaflow operations.

If MCP is not available and a Supaflow slash command covers the task, you ABSOLUTELY MUST use that command.

This is not negotiable. This is not optional. You cannot rationalize your way out of this by saying the task is simple, exploratory, or just needs one quick check.
</EXTREMELY-IMPORTANT>

## Instruction Priority

Supaflow skills and commands override default assistant behavior, but user instructions always take precedence:

1. **User instructions** (`AGENTS.md`, direct requests, repo conventions) -- highest priority
2. **Supaflow skills and commands** -- override default assistant behavior where they conflict
3. **Default system behavior** -- lowest priority

If the user explicitly asks you not to use MCP or a command, follow the user. Otherwise, use the active Supaflow workflow.

## Using Supaflow Commands and Skills

## The Rule

**Run the setup gate BEFORE any response or action that touches Supaflow.** The setup gate chooses the execution surface.

- Desktop MCP path: use `mcp__supaflow__*` tools and the MCP workflow specs. MCP workflows are authoritative when they intentionally differ from slash-command wording.
- Terminal CLI path: invoke the relevant slash command before improvising the workflow in chat.
- If no MCP tool or command exists, use the relevant Supaflow reference skill for domain knowledge and keep the workflow lightweight and explicit.

## HARD RULES

These rules are non-negotiable. Violating any of them is a bug.

1. **Prefer MCP when it exists.** If `mcp__supaflow__auth_status` is available, use MCP tools for Supaflow operations and do not fall back to `Bash(supaflow *)`.
2. **Use commands when MCP is absent and commands exist.** If a command covers the user's request in a terminal CLI session, invoke it. Do not recreate the same workflow freehand in chat.
3. **Ask one question at a time.** Never batch multiple blocking questions into one message.
4. **Do not infer approval from a partial answer.** If the user changes one field, that is not approval for the rest.
5. **Do not create before explicit confirmation.** Pipelines, datasources, schedules: show the user what you are about to create and wait for explicit approval. MCP approval prompts are not a substitute for this confirmation.
6. **Do not guess output fields.** Use only documented field names. If you are unsure, inspect the real MCP/CLI JSON output shape.
7. **Do not ask for passwords or secrets in chat.** Tell the user to edit the env file directly.
8. **Stop on errors.** If a create/edit command or MCP tool fails, show the error verbatim and ask the user what to do. Never silently retry, rename, auto-increment, or "fix" the input without approval.
9. **Always run the init-equivalent before create.** In Desktop MCP mode, use `pipelines_prepare_create` before `pipelines_create_from_plan`. In CLI fallback mode, run `pipelines init` before `pipelines create`. Present actual config values from the generated result/file and wait for explicit confirmation.
10. **Object scope is a required decision.** Ask whether to sync all objects or a subset. In guided MCP mode, pass `object_selection: { "mode": "all" }` for all objects; the MCP wrapper still passes the prepared object file internally. In raw CLI fallback mode, only omit `--objects` after the user explicitly says to sync all discovered objects.
11. **Parse JSON deliberately.** For CLI commands, parse JSON with `python3 -c`. For MCP tools, parse the returned JSON text and use the same field contracts. Never dump full JSON output into the conversation.
12. **In shell loops, never use `status` as a variable name** (read-only in zsh). Use `job_status` or `poll_status`.
13. **Read `mcp-safe-executor.md` before any non-read-only MCP tool.** Follow its read-confirm-call-verify sequence.
14. **Never paste credential material.** Do not quote datasource `configs`, encrypted secret blobs, env file contents, passwords, tokens, API keys, or credential-shaped values. Summarize only safe identifiers and capability fields.
15. **Dependency installs require explicit confirmation** (see the setup gate). Never run `npm install` (or any environment-mutating install/upgrade) silently. Offer it, wait for an explicit yes, then run it. Never auto-install Node. Never paste an API key into chat -- have the user run `supaflow auth login` themselves.

## Red Flags

These thoughts mean STOP. You are rationalizing your way out of the active Supaflow workflow.

| Thought | Reality |
|---|---|
| "This is just a simple pipeline setup" | Simple Supaflow tasks still need the MCP/command guardrails. |
| "I need to ask a few questions first" | Run the setup gate and use the active workflow before freeform clarifying. |
| "Let me inspect the output quickly from memory" | Use MCP/CLI JSON and inspect the real shape. |
| "I can probably use the defaults" | Use `pipelines init`, read the generated file, and show actual values. |
| "The user only changed one field, so the rest is fine" | Partial edits are not approval. Re-show the full final config. |
| "I can retry with a different name/prefix" | Silent retries are a bug. Stop and ask. |
| "I already know the job fields" | The CLI contract is the source of truth, not memory. |
| "This doesn't need a command or MCP tool" | If a Supaflow workflow exists, use it. |
| "I'll just sync all objects by default" | Object scope is a required question. Ask first. |
| "I can trigger the sync with a quick tool call" | Use the sync workflow. It has the correct response parser and polling contract. |
| "MCP asked for approval, so that is enough" | MCP approval is tool approval only. It is not workflow confirmation. |
| "The datasource JSON is read-only, so I can paste it" | Datasource details can include encrypted secrets. Redact configs and credential-shaped values. |

## Conversation Discipline

These rules apply to every Supaflow workflow:

1. Ask one question at a time.
2. Ask only the next blocking question. Do not combine datasource choice, object selection, config approval, and duplicate-handling into one message.
3. After each user answer, update your understanding and ask only the next blocking question.
4. If the user gives a partial answer, do not infer approval for the remaining fields.
5. When a command requires confirmation, present the actual values and wait.
6. If the command fails, show the error and ask what the user wants to do next.

## Available Commands

Use these commands for the corresponding user intents. In the terminal CLI path, invoke the command. In the Desktop MCP path, use MCP workflow specs first; command files are fallback/reference material only where the MCP workflow explicitly points to them.

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

## MCP Tool Safety

For Desktop MCP workflows, read `mcp-safe-executor.md` before calling any non-read-only `mcp__supaflow__*` tool. If a CLI workflow step depends on editing a host-side file generated by MCP and no dedicated MCP tool can perform that exact edit, STOP and ask the user to edit the file on the host or switch to a terminal CLI session. Do not pretend cowork-VM file tools can edit host MCP files.

For Desktop MCP job workflows and guided pipeline creation, read `mcp-workflows.md` and follow its exact resolution, confirmation, and parser rules.

## Before Any Supaflow Operation

Setup gating is owned by the **setup gate** (`setup-preamble.md`), which the SessionStart hook injects ahead of this skill. Do not restate or fork its policy here.

Before any datasource / pipeline / job / schedule action, ensure the active gate passes. If MCP is available, verify via `mcp__supaflow__auth_status` and use MCP. If MCP is absent, use the CLI gate: Node >= 18; the Supaflow CLI present and current (offer + confirm before installing -- never silently, never auto-install Node); authenticated (the user runs `supaflow auth login` themselves -- no API key in chat); and a workspace selected. If any check fails, follow the gate: resolve it or hand the user the exact fix, then STOP until it passes. The SessionStart "CLI Path Setup Issues" list reports CLI fallback checks only.

## Parser Contracts

These are the correct JSON field names for each CLI output. Never invent alternatives.

**`jobs status --json`:** `id`, `job_status`, `status_message`, `job_response`
- NEVER use: `phase`, `duration`, `completed_at`, `progress`

**`jobs get --json`:** `execution_duration_ms`, `ended_at`, `job_response`, `object_details`
- NEVER use: `duration`, `completed_at`, `objects`, `rows_read`

**`pipelines list --json` / `datasources list --json`:** wraps results in `{ "data": [...], "total": N, "limit": N, "offset": N }`
- Default limit is 25. **Use limit 200** for broad scans to avoid silently missing items. The pipelines list command caps at 200; do not rely on a datasource cap.
- Always check `total > len(data)` and warn the user about truncation.
- **For exhaustive scans** (duplicate checks, deletion verification): page with `--offset` until `len(batch) < limit`. A single page is NOT authoritative.
- **For single-item lookups**: prefer `pipelines get <identifier>` or `datasources get <identifier>` which resolve directly without pagination.
- Pipeline items use nested fields: `source.name`, `source.datasource_id`, `destination.name`, `destination.datasource_id`, `project.id`, `project.name`
- NEVER use flat fields like `source_name` or `project_api_name`

**`pipelines schema list --json`:** returns a raw JSON array (NOT wrapped in `{ data: [...] }`). Each item uses `fully_qualified_name`, `selected`, `fields`
- This is the same shape consumed by `pipelines schema select --from`
- Default to selected objects only. Use `--with-fields` when preserving or editing field selections.
- Use `--all` only when the task requires currently deselected objects; it scans the full catalog and can produce very large output.
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
