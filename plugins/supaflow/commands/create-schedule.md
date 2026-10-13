---
description: Create a recurring Supaflow schedule through hosted MCP
argument-hint: "[pipeline-and-frequency]"
---

# create-schedule

This is a hosted-MCP workflow, not a local command. Follow [the connection and workspace gate](../skills/using-supaflow/SKILL.md) and [safety rules](../skills/using-supaflow/safety.md), then read [supaflow-schedules](../skills/supaflow-schedules/SKILL.md).

Check existing schedules and resolve the target. Clarify cadence and timezone, show the five-field cron and final target/name, obtain explicit final approval, call `schedules_create`, and verify the complete schedule inventory. Do not automatically run the schedule.

Use only the actual Supaflow connector tools, passing the resolved `workspace_id` on every scoped call. If the connection or required capability is unavailable, stop and guide the user to the connector UI or Supaflow dashboard. Do not use a shell or local-agent fallback.
