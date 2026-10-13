---
description: Prepare and create a pipeline through hosted Supaflow MCP
argument-hint: "[source-to-destination]"
---

# create-pipeline

This is a hosted-MCP workflow, not a local command. Follow [the connection and workspace gate](../skills/using-supaflow/SKILL.md) and [safety rules](../skills/using-supaflow/safety.md), then read [supaflow-pipelines](../skills/supaflow-pipelines/SKILL.md).

Discover existing datasources, destination projects, and duplicate pipelines first. Use `pipelines_prepare_create`, show the actual config and object scope, and obtain explicit final approval before `pipelines_create_from_plan`. Verify the saved pipeline and complete selected-object pages; do not automatically run it.

Use only the actual Supaflow connector tools, passing the resolved `workspace_id` on every scoped call. If the connection or required capability is unavailable, stop and guide the user to the connector UI or Supaflow dashboard. Do not use a shell or local-agent fallback.
