# Plugin distribution and migration

## Source boundaries

The repository's `.claude-plugin/marketplace.json` is a catalog. It points at two self-contained packages:

- `plugins/supaflow`: original identity `supaflow`, display name Supaflow, hosted HTTP MCP only.
- `plugins/supaflow-code`: identity `supaflow-code`, display name Supaflow Code, local CLI-backed stdio MCP plus CLI workflows; supported in Claude Code only.

Keep the existing marketplace name `supaflow` so repository registration remains stable. Plugin entry names match the corresponding manifest names. Source paths are relative to the repository root. Every package contains its own README, license, manifest, MCP config, and referenced skill files; no sibling or repository-root runtime dependency is allowed.

The editions have different execution contracts, not duplicate backends. The hosted package calls the existing production service with OAuth and an explicit workspace ID. The Code package uses the existing CLI's authentication and local selected-workspace state. Do not copy local CLI parser fields, file exports, or agent tools into hosted instructions.

## Public directory versus GitHub installs

Submit only `plugins/supaflow` for the MCP-only public listing. Do not upload the repository root, which contains both editions and contributor tests. A ZIP must contain the contents of that folder or that folder as its sole top-level entry.

Supaflow Code is distributed through this repository's GitHub marketplace. Users add the repository, then install `supaflow-code@supaflow`. Do not submit the Code package as the browser/Desktop marketplace edition, or imply it works in sandboxed chat environments.

A source change or ZIP creation does not install, authenticate, submit, approve, or publish anything. Those are separate operations requiring explicit authorization.

## Existing local-plugin users

Previously the repository root itself was the `supaflow` CLI plugin. After updating their registered GitHub marketplace:

1. Users who want to keep local workflows install `supaflow-code@supaflow`.
2. Disable/uninstall the previous `supaflow` edition if it is no longer wanted; do not remove a user's other connectors, credentials, or local agent.
3. Users choosing hosted workflows install `supaflow@supaflow`, add/connect its remote connector, and complete OAuth for the intended Supaflow account.
4. Verify the actual auth identity and workspace through the selected edition. A connection's display label or the Claude account's name is not proof of the Supaflow identity.

Do not silently migrate CLI keys into OAuth settings or delete an old local MCP registration. Explain the distinction and let the user choose one edition per workflow.

## Tool approvals

Hosted MCP annotations classify tools but do not grant persistent permission. Claude users/admins control `Always allow`, `Needs approval`, or `Blocked` under the connector's tool permissions.

The Code edition's command `allowed-tools` frontmatter applies to local Claude Code invocation only. It is not a hosted-plugin permission default and does not automatically authorize deletion, resets, cancellation, dependency installation, or local-agent lifecycle changes.

The single hosted run tool also accepts full-resync/target-reset flags, so persistently allowing it is broader than allowing only normal syncs. Keep that distinction visible when discussing permissions.

## Verification

Offline preparation:

```bash
claude plugin validate .
claude plugin validate ./plugins/supaflow
claude plugin validate ./plugins/supaflow-code
bash tests/run-tests.sh
bash tests/run-tests.sh --medium
```

Before publishing, explicitly authorize and test each chosen host/package:

- Hosted: install the Supaflow package, connect through OAuth, verify the intended personal/org identity and workspace, list datasources/pipelines, traverse sparse selected-object pages, and run one authorized normal sync while monitoring its specific job to terminal.
- Code: load/install Supaflow Code in Claude Code; verify the local CLI account/workspace, stdio discovery, hook setup behavior, namespaced command loading, and requested local workflows. Local-agent changes need their own explicit authorization.
- A previously working bare connector does not prove the newly packaged skills were installed or exercised.
- A failed terminal sync proves dispatch/monitoring, not successful replication; fix the destination/source issue and obtain authorization before retrying.
- Do not weaken client permission settings to make a test look successful.

Offline tests validate package contents and contract fixtures; they do not execute a language model or prove production behavior. Slow/live suites are opt-in; never run them as a substitute for the user's authorization.

## Official format references

- [Plugin structure and testing](https://claude.com/docs/plugins/build)
- [Platform support](https://claude.com/docs/plugins/platform-support)
- [Marketplace source entries](https://code.claude.com/docs/en/plugins/create-marketplace#add-plugin-entries)
- [Claude Code skill tool permissions](https://code.claude.com/docs/en/skills#pre-approve-tools-for-a-skill)
