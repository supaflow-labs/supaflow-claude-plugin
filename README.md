# Supaflow plugins for Claude

This repository is the GitHub marketplace for two independent [Supaflow](https://www.supa-flow.io) plugin packages. Both operate the existing Supaflow platform; neither implements a new MCP server. Choose one edition for a workflow so local CLI credentials cannot be confused with a hosted OAuth connection.

| Package | Installable name | Intended use | Execution surface |
| --- | --- | --- | --- |
| [Supaflow](plugins/supaflow/README.md) | `supaflow` | Public marketplace submission; Claude web, Desktop chat, Cowork, and hosted workflows in Claude Code | Production HTTP MCP with OAuth; no local executable |
| [Supaflow Code](plugins/supaflow-code/README.md) | `supaflow-code` | GitHub installs in Claude Code with a local shell | Local CLI-backed stdio MCP, CLI commands, and private-agent lifecycle support |

## Install from GitHub in Claude Code

Register the repository as a marketplace, then install the desired edition by its full ID:

```bash
claude plugin marketplace add https://github.com/supaflow-labs/supaflow-claude-plugin.git
claude plugin install supaflow-code@supaflow
```

For MCP-only workflows in Claude Code, choose `supaflow@supaflow` instead. Installing the repository's marketplace does not install both plugins. These commands fetch the published GitHub revision, not uncommitted local changes.

For Claude web, Desktop chat, and Cowork, use the **Supaflow** package. Add a published marketplace through **Customize > Plugins > Add > Add marketplace**, or upload only the `plugins/supaflow` folder as a ZIP for a private test. Open the plugin's **Connectors** tab, add/connect Supaflow, and complete OAuth for the intended account/workspace. Adding a plugin alone does not authenticate its connector. The public directory listing requires a separate submission and approval; this restructuring does not publish either package.

## Layout

```text
.claude-plugin/marketplace.json
plugins/
  supaflow/
    .claude-plugin/plugin.json
    .mcp.json
    commands/
    skills/
    README.md
    LICENSE
  supaflow-code/
    .claude-plugin/plugin.json
    .mcp.json
    commands/
    skills/
    hooks/
    README.md
    LICENSE
tests/
docs/
```

The repository root is a marketplace, not an installable plugin. Every marketplace `source` points at one self-contained folder. There are no cross-package symlinks or runtime imports.

## Develop and validate without installing

```bash
claude plugin validate .
claude plugin validate ./plugins/supaflow
claude plugin validate ./plugins/supaflow-code
bash tests/run-tests.sh
bash tests/run-tests.sh --medium
```

The default suite checks both package boundaries, manifests, skills, local hook behavior, and command frontmatter. Medium adds offline hosted-contract regressions and existing CLI parser/workflow guards. No dependency installation or authenticated service calls are required.

For an explicitly authorized interactive local test, load one package, not the repository root:

```bash
claude --plugin-dir ./plugins/supaflow-code
```

This starts a real session and can launch the configured local MCP process. Validate/static-test commands do not install a plugin or launch a test session.

`--slow`, `--live`, and `--all` use Claude or an authenticated Supaflow CLI and may call external services or mutate a workspace. They are opt-in and require explicit authorization. Do not use them as offline verification.

## Migration and distribution

Existing users who installed `supaflow` for local CLI workflows should install `supaflow-code@supaflow` instead. The original `supaflow` identity is retained for hosted MCP. CLI credentials and hosted OAuth grants remain separate; do not reuse a connection label as proof of identity.

See [distribution and migration](docs/PLUGIN_DISTRIBUTION.md) for package-only submission boundaries, account verification, host permission controls, and live-test expectations. Runtime edits increment the affected package's version.

## License

MIT. Each installable package includes the repository license.
