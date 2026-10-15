# Supaflow

Build and run data pipelines directly in Claude. Move data across SaaS apps, databases, data warehouses, and data lakes. Transform data using dbt Core™ models and sync data to your business apps with reverse ETL. Orchestrate pipelines, manage schedules, and troubleshoot issues—all through conversation.

This is the hosted-MCP-only marketplace edition. It works in Claude web, Desktop chat, Cowork, and Claude Code without installing a local executable or configuring local files.

## Connect

You need a Supaflow account: [create one](https://app.supa-flow.io/sign-up) or [sign in](https://app.supa-flow.io/sign-in). See the [Claude setup guide](https://www.supa-flow.io/agentic-data-pipelines/claude-plugin) for the hosted and separate Code editions.

1. Install **Supaflow** from its published listing/marketplace, or upload this plugin folder as a ZIP for private testing.
2. Open the plugin's **Connectors** tab and add/connect Supaflow.
3. Complete OAuth for the intended Supaflow account. If password sign-in is needed and an email-code page appears, choose **Use another method** and then **Sign in with your password**. Enter credentials only in Supaflow's sign-in form, never in chat.
4. Ask Claude to verify the authenticated identity and accessible workspaces. Choose a workspace if more than one matches your request.
5. Ask **“Help me get started with Supaflow: check my workspace and connections, and explain what I need next.”** Where slash commands are supported, use `/supaflow:setup`. The bundled onboarding skill performs read-only checks and explains missing setup; it does not run automatically on installation or authorize changes. Configure missing source/destination credentials securely in the Supaflow dashboard before creating or running pipelines.

The bundled server is `https://app.supa-flow.io/mcp`. It is the production server, not localhost and not a local process. The plugin does not ship credentials, a hard-coded OAuth client ID/secret, or a callback URL; the host and server handle discovery and authentication.

## Example prompts

- List my available datasources, showing each name, connector type, and state.
- List my pipelines and show their sources and destinations.
- Show my five most recent jobs, newest first.
- Show the source, destination, and selected objects for my Salesforce-to-Snowflake pipeline.
- Run my Salesforce-to-Snowflake pipeline using a normal sync, monitor that job to completion, and summarize its outcome.

Names are examples, not preconfigured resources. Resolve them from the connected account. Missing metrics/configuration are reported as unavailable rather than invented.

## Workflows

The `using-supaflow` skill resolves the connection and workspace and routes to datasource, pipeline, job, or schedule skills. Commands expose the same hosted workflows. In chat they can load as skills; where slash commands are supported, use names such as `/supaflow:sync-pipeline` or `/supaflow:create-pipeline`.

A normal sync preserves selected objects and configuration and uses `full_resync: false` and `reset_target: false`. New resources require review of the actual configuration and object scope. Deletion, job cancellation, catalog reset, full resync, and target reset require explicit confirmation. The hosted server cannot manage the local lifecycle of a private agent; use **Supaflow Code** in Claude Code or the dashboard's agent setup workflow for that.

## Permissions and data

OAuth access is limited by the consenting user's Supaflow permissions and scopes. Every resource operation passes an explicitly resolved workspace ID. A personal account can legitimately have no organization ID.

Claude sends authorized tool arguments to Supaflow's hosted MCP server, which returns accessible metadata, configuration defaults/plans, object selections, job metrics, and stored job responses. Datasource credential configs are not returned; plaintext secrets must not be supplied through chat or tool input. The plugin contains instructions and a server reference, not a separate data store. Conversations and tool results are also processed by the Claude host under its own policies.

Claude's **Tool permissions** settings are user/administrator controls. This package does not preapprove tools or bypass confirmation. Read-only tools can be allowed persistently by the user; write/destructive tools should be reviewed according to the account's risk policy.

Documentation: https://www.supa-flow.io/docs

Support: support@supa-flow.io

License: MIT
