# Decisions

Durable design decisions: context, decision, reason. Not a task tracker.

## CLI-only, zsh

FEFO is one zsh CLI, no other runtimes in its own code. Linux/macOS only.
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

## Vault-first + scoped grep; FEFO graph

Read generated per-repo code vaults first (`fefo vault`,
`docs/vault/<slug>-vault/00-INDEX.md` → module note → `path:line`), then
verify usages with scoped `git grep` inside the listed files; never grep a
whole repo before reading its index. Knowledge notes in `docs/vault/` are plain
Markdown. `fefo vault --changed` refreshes vaults and `docs/vault/graph.json`
at session start; both are generated and gitignored.

FEFO owns one graph over all vault Markdown (code vaults plus hand-written
notes), built in zsh and queried with `fefo graph --query <term>`. It is an
index over the vault, never a replacement for it; no MCP server or external
CLI. The browse MCP is opt-out per workspace (`browse off`). Automations are
not generated: they are runtime state and a security decision.

## Handoff root /var/tmp/fefo

Handoffs live outside the repos at `/var/tmp/fefo/<ws-slug>/<task>` (mode 700)
so lane reports never pollute Git.

## Model modes and fallback

`cheap` pins the strongest free model; `default` pins one chosen model. Fallback
is always on: sibling provider, then the strongest other free model, then the
owner's own model. Variant is never asked; the highest is used.

## Installation built in

FEFO is the whitelabel; installation built in: `install.sh` + `install.zsh` +
`share/fefo.zsh` in this repo, which downloads FEFO as a tarball and installs
the CLI plus the cmg/bng/doit helpers.

## Agents: default or AI

`fefo agents` installs the copied default set (offline) or AI-scoped agents.
Only the `vault-search` skill ships.
