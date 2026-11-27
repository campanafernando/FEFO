# Decisions

Durable design decisions: context, decision, reason. Not a task tracker.

## CLI-only, zsh

FEFO is one zsh CLI (no other runtimes in its own code; the only non-zsh
file is `lib/vault-graph.mjs`, run by CodeGraph's bundled Node). Linux/macOS only.
Reason: less to maintain and install.

## OpenCode-first, basic Claude Code support

OpenCode is the primary harness (model pinning, subagent policy). With
`claude on` (default; `fefo init --no-claude` disables), `fefo sync` also writes
`CLAUDE.md`, `.mcp.json` and `.claude/skills/`. No Claude agents, commands,
settings or hooks are generated. Requires OpenCode latest, minimum 2.4.2;
`fefo doctor` warns when OpenCode is behind the latest release
(`FEFO_SKIP_UPDATE_CHECK=1` skips the check for CI/offline).

## Method lives in AGENTS.md

The orchestration method is generated into `AGENTS.md`, so any OpenCode session
follows it with no FEFO agent, plugin or slash command. The manifest is
`.fefo/workspace.zsh`, a line-oriented DSL that is never sourced.

## One codegraph server, absolute projectPath

A single `codegraph` MCP server serves every index; callers pass the absolute
`projectPath`. CodeGraph is opt-out per repository (`codegraph=off` on the
`repo` line, or `codegraph off` for the workspace) so docs-only orchestrators are
never indexed; the browse MCP is opt-out per workspace (`browse off`). Automations are not generated: they are runtime
state and a security decision.

## Vault graph via `fefo index --vault`

Markdown is not a CodeGraph language, so notes are indexed into a companion
SQLite graph, served by a separate `vault` server with `--no-watch`.
`fefo graph` renders it.

## Handoff root /var/tmp/fefo

Handoffs live outside the repos at `/var/tmp/fefo/<ws-slug>/<task>` (mode 700)
so lane reports never pollute Git.

## Model modes and fallback

`cheap` pins the strongest free model; `default` pins one chosen model. Fallback
is always on: sibling provider, then the strongest other free model, then the
owner's own model. Variant is never asked; the highest is used.

## Installation via fefo-install

FEFO is the whitelabel; installation lives only in fefo-install, which
downloads FEFO as a tarball and installs the CLI plus the cmg/bng/doit helpers.

## Agents: default or AI

`fefo agents` installs the copied default set (offline) or AI-scoped agents.
Only the `codegraph` and `vault-search` skills ship.
