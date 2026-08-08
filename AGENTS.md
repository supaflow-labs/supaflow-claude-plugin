# Supaflow Claude Plugin Guidelines

- The workspace rules in `../AGENTS.md` also apply.
- Every installed/runtime plugin content change must update the semantic version in `.claude-plugin/plugin.json` in the same change so clients can receive it. Runtime surfaces include the manifest, commands, skills, hooks, and `.mcp.json`. Contributor-only repository guidance such as `AGENTS.md` does not change installed behavior and does not by itself require a version bump.
- Run `tests/run-tests.sh` for installed/runtime plugin changes. For contributor-only guidance, at minimum run `git diff --check` and review the complete documentation diff.
- Any `--live` or publish/install action that changes an external or user-wide environment requires explicit authorization for the current request.
- Never place API keys, login commands containing keys, credentialed URLs, or environment-file contents in plugin examples, tests, fixtures, or memory. Use obvious placeholders.
- Keep ordinary commit and PR prose focused on the feature and verification; do not add release mechanics unless the user explicitly requested a release change.
