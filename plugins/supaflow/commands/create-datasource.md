---
description: Create a datasource through hosted Supaflow MCP
argument-hint: "[connector-or-datasource]"
---

# create-datasource

This is a hosted-MCP workflow, not a local command. Follow [the connection and workspace gate](../skills/using-supaflow/SKILL.md) and [safety rules](../skills/using-supaflow/safety.md), then read [supaflow-datasources](../skills/supaflow-datasources/SKILL.md).

Create a datasource only after discovering existing ones, retrieving connector properties with `datasources_init`, and reviewing the final safe configuration. Use the dashboard/OAuth or supported encrypted/server-side-copy flow for credentials. Never ask for plaintext secrets. Verify the returned datasource and any connection-test job.

Use only the actual Supaflow connector tools, passing the resolved `workspace_id` on every scoped call. If the connection or required capability is unavailable, stop and guide the user to the connector UI or Supaflow dashboard. Do not use a shell or local-agent fallback.
