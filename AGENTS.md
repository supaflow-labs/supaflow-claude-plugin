# Supaflow Claude Plugin Guidelines

- The workspace rules in `../AGENTS.md` also apply.
- The repository root is a marketplace, not an installable plugin. Its `.claude-plugin/marketplace.json` points to two self-contained packages: `plugins/supaflow` (hosted MCP only) and `plugins/supaflow-code` (Claude Code local CLI and CLI-backed MCP). Keep their names distinct and their source paths contained within this repository.
- Every installed/runtime plugin content change must update the semantic version in that package's `.claude-plugin/plugin.json` in the same change so clients can receive it. Runtime surfaces include the manifest, commands, skills, hooks, and `.mcp.json`. Contributor-only repository guidance such as `AGENTS.md` does not change installed behavior and does not by itself require a version bump.
- `plugins/supaflow` must remain self-contained and hosted-MCP-only: no local process MCP server, shell scripts, CLI installation/authentication instructions, hooks, filesystem credential workflows, or local-agent lifecycle tools. Do not copy CLI output contracts into its hosted workflows. Every workspace-scoped hosted call must pass the explicitly resolved `workspace_id`.
- Keep local shell workflows, agent lifecycle support, and CLI-backed stdio MCP inside `plugins/supaflow-code`. Do not advertise that package as supported in web chat, Desktop chat, or Cowork. Do not add a second hosted MCP implementation.
- Use `tests/run-tests.sh --medium` for offline verification of both package boundaries and existing CLI guardrails. `--slow`, `--live`, and `--all` can call authenticated external services; they require explicit authorization for the current request.
- Follow `docs/PLUGIN_DISTRIBUTION.md` for package-only distribution, migration, permission controls, and explicitly authorized live verification. Validate both package folders and the marketplace root before handoff.
- Run `tests/run-tests.sh` for installed/runtime plugin changes. For contributor-only guidance, at minimum run `git diff --check` and review the complete documentation diff.
- Any `--live` or publish/install action that changes an external or user-wide environment requires explicit authorization for the current request.
- Never place API keys, login commands containing keys, credentialed URLs, or environment-file contents in plugin examples, tests, fixtures, or memory. Use obvious placeholders.
- Keep ordinary commit and PR prose focused on the feature and verification; do not add release mechanics unless the user explicitly requested a release change.

## SDLC, PR requirements, and review

- For ordinary work, use a task branch and a PR to `main`; preserve existing changes and keep unrelated commits out of the PR. Read applicable scoped instructions, implement the smallest agreed change, run the relevant local checks, and review the whole diff. Commit/push only within explicit user approval; merge only when authorized, using a merge commit. Separately authorized release-script exceptions below remain exceptions.
- Fill in [.github/pull_request_template.md](.github/pull_request_template.md). Include the request/specification source, testable acceptance criteria, before/after behavior, deliberate product constraints with rationale, non-goals, verification evidence and gaps, and relevant cross-repository dependencies. Copy essential decisions into the PR; reviewers may not have the workspace or conversation. Update the description when scope or decisions change.
- Reviewers must assess the implementation against that contract and this repository's invariants. Report a defect only with a concrete scenario, code evidence, and a violated requirement or invariant. Accepted product constraints are not missing features; optional enhancements and ambiguous requirements are separate questions. An intentional constraint cannot excuse a regression, security flaw, or data-integrity defect.
- Address valid findings with focused fixes and appropriate regression coverage. For a disputed finding, record the requirement and evidence supporting its disposition before resolving it; involve the owner when the requirement is unclear. Do not repeatedly reopen a resolved decision without new evidence, change product behavior merely to quiet a reviewer, or dismiss unresolved defects to pass a gate.
- Before merging, require successful applicable checks, resolved conversations, and completed review of the current PR head/base. New commits need fresh evidence. Do not bypass GitHub rules, forge a passing status, or substitute a review request/reaction for completed review. After merge, return to clean updated `main`, remove only this task's merged branches/worktrees, and preserve unrelated work.

- Ordinary changes use PRs to `main`; run the applicable offline package tests and review evidence described below. Verify the main-branch gates described below.
- Preserve runtime package versioning and distribution rules below. A merge alone does not authorize live tests, user-wide installation, or external marketplace publication; contributor-only guidance does not require a runtime version bump.

## Main branch enforcement

- The main-branch protection rollout requires PRs, resolved conversations, merge commits, `PR checks` and `Codex review / main`, with no bypass actors. Verify live rule activation and successful current-head evidence before claiming enforcement.
- `.github/workflows/pr-checks.yml` defines the offline CI coverage. These checks do not prove live credentials, deployments, or database/data correctness. No live test or publication is authorized by CI.
- Keep the Codex connector enabled for this repository and request a fresh review when necessary. Missing or incomplete review is not a pass.

- Choose the intended target branch when opening a PR. If its base branch is changed, close it and open a new PR against the intended base; the review gate rejects retargeted PRs because review summaries identify the head but not the reviewed base.
