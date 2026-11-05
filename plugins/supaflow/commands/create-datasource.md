---
description: Create a datasource through hosted Supaflow MCP
argument-hint: "[connector-or-datasource]"
---

# create-datasource

This is a hosted-MCP workflow, not a local command. Follow [the connection and workspace gate](../skills/using-supaflow/SKILL.md) and [safety rules](../skills/using-supaflow/safety.md), then read [supaflow-datasources](../skills/supaflow-datasources/SKILL.md).

Resolve the intended connection role before configuration: use `role: "SOURCE"` for a source or `role: "DESTINATION"` for a destination. If the request does not establish the intended use, ask; connector type alone does not determine the role. Pass the same explicit role to both `datasources_init` and `datasources_create`, along with the resolved `workspace_id`. Source defaults apply only to omitted configuration properties; preserve explicit choices and review any disabled source discovery before creation. Include the role in the final approval summary.

Create a datasource only after discovering existing ones, retrieving connector properties with `datasources_init`, and reviewing the final safe configuration. Use the dashboard/OAuth or supported encrypted/server-side-copy flow for credentials. Never ask for plaintext secrets. Verify the returned datasource and any connection-test job.

Use only the actual Supaflow connector tools, passing the resolved `workspace_id` on every scoped call. If the connection or required capability is unavailable, stop and guide the user to the connector UI or Supaflow dashboard. Do not use a shell or local-agent fallback.
