---
name: supaflow-datasources
description: Discover, inspect, configure, test, and refresh Supaflow datasources through hosted MCP. Use when the user asks about sources, destinations, connector types, credentials, or discovered objects.
---

# Hosted datasources

First follow [the connection/workspace gate](../using-supaflow/SKILL.md), [safety rules](../using-supaflow/safety.md), and [response contracts](../using-supaflow/response-contracts.md). Every call below includes the resolved `workspace_id`.

## Discover and inspect

1. Use `datasources_list` before requesting new configuration. Page the inventory as documented; prefer `datasources_get` for a known identifier.
2. Show names, IDs, `connectorType`, `connectorName`, and `state` from the actual response. Use `connectors_list` for advertised connector capabilities. Group sources/destinations only when the connector capabilities or project/pipeline linkage support that classification; some connectors support both.
3. Read discovered objects with `datasources_catalog(identifier, refresh: false)` and page the results. Request `with_fields: true` only when needed. Ordinary inspection must not trigger discovery or catalog reset.

## Create and configure

1. Call `datasources_init(connector)` to retrieve the connector properties and required fields. Use `docs` when available for connector-specific prerequisites; do not invent config properties.
2. Resolve non-secret properties and ask only for missing information. For credentials, direct the user to connector OAuth or the datasource form in `https://app.supa-flow.io`. Never request plaintext secrets in chat or MCP input.
3. If an accessible existing datasource can be copied and the user requests that copy, use `datasources_create` with `copy_from_identifier`. Otherwise use only a supported Supaflow encrypted-envelope flow. Do not invent envelope contents or copy another account's identifiers.
4. Show connector, name, destination/source role, non-secret changes, and whether a connection test will run. Obtain explicit approval of the final creation configuration before `datasources_create`.
5. Capture any returned job ID, monitor it using the jobs skill, and reread `datasources_get`. Do not call the datasource ready until the live state and any requested test are successful.
6. Before creating a pipeline, check the source catalog. If discovery is needed, explain it and obtain the user's authorization for `datasources_refresh` or `datasources_catalog(refresh: true)`; monitor the returned discovery job, then reread the catalog.

For edits, read the current datasource, review the exact safe changes, use `datasources_edit` only with supported config values, and reread the datasource/test job. Credentials unavailable through a supported encrypted path must be edited in the dashboard; there is no local-file credential fallback.

## Test, maintenance, and deletion

- `datasources_test` and `datasources_refresh` enqueue jobs; follow `jobs_status` then `jobs_get` for the returned ID. Failed tests must be diagnosed before retrying or creating dependent pipelines.
- `datasources_reset_catalog` is exceptional recovery, not ordinary discovery. Immediately confirm the exact datasource and maintenance impact. Poll `datasources_catalog_reset_status` until `catalog_reset.maintenance_active` is false, then reread the catalog and affected pipeline selections. A terminal job alone is insufficient.
- Before `datasources_delete`, resolve the target, explain dependent pipeline impact, and obtain explicit confirmation immediately before the call. Verify the returned/live deletion state.
