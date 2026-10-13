---
description: Delete a pipeline after explicit confirmation through hosted MCP
argument-hint: "[pipeline]"
---

# delete-pipeline

This is a hosted-MCP workflow, not a local command. Follow [the connection and workspace gate](../skills/using-supaflow/SKILL.md) and [safety rules](../skills/using-supaflow/safety.md), then read [supaflow-pipelines](../skills/supaflow-pipelines/SKILL.md).

Resolve the exact pipeline and workspace, explain its deletion impact, and obtain explicit confirmation immediately before `pipelines_delete`. Verify deletion from the returned state or complete inventory. A tool permission is not deletion authorization.

Use only the actual Supaflow connector tools, passing the resolved `workspace_id` on every scoped call. If the connection or required capability is unavailable, stop and guide the user to the connector UI or Supaflow dashboard. Do not use a shell or local-agent fallback.
