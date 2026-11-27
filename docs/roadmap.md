# Roadmap

## Shipped

- zsh-only CLI (`fefo`) with manifest DSL `.fefo/workspace.zsh`.
- OpenCode-first: single `opencode.json`; basic Claude Code support.
- One CodeGraph MCP server with absolute `projectPath`; separate `vault`
  server with `--no-watch`.
- Vault graph from Markdown + `fefo graph` viewer.
- Worktree-aware `fefo index` with seeding.
- Default or AI-scoped agents; `codegraph` and `vault-search` skills.
- `fefo handoff` protocol and `fefo graph`.

## In progress

- Test suite.
- `fefo agents --ai` non-interactive OpenCode job.
- Vault graph viewer polish.

## Planned

- Automatic OpenCode update process with the same version gate.
- Optional semantic search over the vault.
- Link repository notes to CodeGraph symbols and source paths.
- `fefo vault` for index and link validation.
