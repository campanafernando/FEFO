# Roadmap

## Shipped (v2)

- zsh-only CLI (`fefo`) with manifest DSL `.fefo/workspace.zsh`.
- OpenCode-only: single `opencode.json`, no IDE adapters.
- One CodeGraph MCP server with absolute `projectPath`; separate `vault`
  server with `--no-watch`.
- Vault graph from Markdown + `fefo graph` viewer.
- Worktree-aware `fefo index` with seeding.
- Default or AI-scoped agents; `codegraph` and `vault-search` skills.
- Bonus shell functions `cmg`, `bng`, `doit`.
- `fefo handoff` protocol and `fefo graph`.

## In progress

- Installer (`install.zsh`) and test suite for the zsh rewrite.
- `fefo agents --ai` non-interactive OpenCode job.
- Vault graph viewer polish.

## Planned

- Automatic OpenCode update process with the same version gate.
- Optional semantic search over the vault.
- Link repository notes to CodeGraph symbols and source paths.
- `fefo vault` for index and link validation.

## Removed (and why)

- Python CLI and tests: replaced by zsh; only `lib/vault-graph.mjs` remains
  (CodeGraph's bundled Node).
- IDE adapters for Cursor/Copilot: OpenCode is the primary harness. Basic
  Claude Code CLI support ships via `CLAUDE.md`, `.mcp.json`, and
  `.claude/skills/` when `claude on`.
- Slash commands, modes, plugins, and the `fefo` primary agent: orchestration
  lives in `AGENTS.md`.
- Windows/PowerShell paths: Linux/macOS zsh only.
- Multi-harness sync and adapter checks.