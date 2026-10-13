---
name: supaflow-schedules
description: Inspect, create, edit, enable, disable, delete, or run Supaflow schedules through hosted MCP. Use when the user asks for recurring pipeline syncs, cron timing, timezone changes, or schedule history.
---

# Hosted schedules

Follow [the connection/workspace gate](../using-supaflow/SKILL.md), [safety rules](../using-supaflow/safety.md), and [response contracts](../using-supaflow/response-contracts.md). Every call includes the resolved `workspace_id`.

1. List and page `schedules_list` before creating a schedule. Resolve the existing target pipeline by its actual ID; do not create redundant schedules for the same target/timing without the user's explicit choice.
2. Clarify frequency and timezone. Convert the request to a five-field cron expression supported by the service. Show the exact timezone and human-readable cadence; do not silently assume the user's local timezone or UTC.
3. For creation, show name, target, cron, and timezone, then obtain explicit final approval before `schedules_create`. Pass one target supported by the loaded schema (`pipeline`, `task`, or `orchestration`), not multiple targets.
4. Creation returns `schedule.id` and `schedule.cron`; inventory rows use `cron_schedule`. Verify the created schedule by ID using a complete `schedules_list` traversal and compare timing, target, timezone, and state.
5. For edits or enable/disable requests, resolve the existing schedule, show the exact change, obtain authorization, call the relevant operation, and verify the inventory afterward. Do not treat an edit request as authorization to run the schedule.
6. Immediately confirm the resolved schedule before `schedules_delete`. Explain that deletion stops future scheduled executions and verify the returned/live state.
7. Run `schedules_run` only when requested and follow the execution-resolution workflow below. Its response acknowledges a trigger, not job creation or completion. Use `schedules_history` for execution status and previous executions.

## Resolve and monitor a requested schedule run

1. Resolve the exact schedule and workspace from `schedules_list`, including its target. Before triggering, read `schedules_history(identifier: schedule_id)` and record the existing `execution_id` values as a baseline. If the baseline cannot be read, stop and explain the monitoring limitation before triggering; do not silently substitute an older job.
2. Call `schedules_run` once. Its current response is `schedule.id` and `schedule.status: "triggered"`; it does not return a job ID. Never pass the schedule ID or an execution ID to `jobs_status`, `jobs_get`, or `jobs_logs` as if it were a job ID.
3. Read `schedules_history` again for the same schedule/workspace. Resolve a new execution using its actual `execution_id` and `triggered_at`, comparing with the pre-trigger baseline. Do not simply choose the latest execution or the latest target-pipeline job: those may belong to an older or concurrent run. If history has not caught up, use bounded read-only polling; do not trigger another run.
4. Once one execution is unambiguously resolved, monitor that same execution through `schedules_history`, matching its `execution_id` on every poll. Report the returned execution status, completion time, entry counts, duration, and error message only when present. A task/orchestration schedule can represent more than one job; do not invent a single pipeline job for it.
5. Poll job tools only if an actual returned response explicitly links a real job ID to that resolved execution. Use that associated job ID with `jobs_status` and terminal details, not the schedule ID, execution ID, or an unrelated `jobs_list` result. Current schedule history exposes execution metadata but does not guarantee a job-ID association; execution-history monitoring is valid without one.
6. If there is no new execution, multiple new executions cannot be correlated unambiguously, or the resolved execution is no longer present in the accessible history window, report that the trigger was accepted but the requested execution cannot be resolved/monitored. Include the schedule ID and last verified state; do not claim completion, invent an associated job, widen to another workspace, or rerun the schedule. If the execution is resolved but still nonterminal when monitoring stops, report that execution ID and last observed state instead.

Do not manage local operating-system schedules or fall back to local programs. On an ambiguous mutation result, reconcile existing schedules/jobs before repeating it.
