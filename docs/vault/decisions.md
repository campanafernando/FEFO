# Decisions

Record durable decisions here with date, context, decision, and consequence.
Do not use this file as a task tracker.

## 2026-11-23 — Adopt OpenCode 2.4 in the whitelabel generator

Context: OpenCode 2.4 added a built-in desktop browser, automations, image and
video generation, a new TUI look, and Windows taskbar status. The generated
config still assumed the pre-2.4 browse MCP and indexed every federated
repository, including documentation-only orchestrators.

Decision:

- Require OpenCode 2.4.2+ and the latest published CLI. Mutating `fefo` commands stop when a newer version is available;
  `FEFO_SKIP_UPDATE_CHECK=1` is limited to CI/offline use.
- Patch releases bump the floor and refresh the cached latest manually until the
  automatic updater ships; 2.4.2 is the current floor.
- Document 2.4 as the floor, not a feature tour: the docs point to the OpenCode
  release notes and enforce the version instead of repeating the changelog.
- Make CodeGraph opt-out per repository (`"codegraph": false`). A docs-only
  orchestrator should not spawn an index-less MCP server or produce a false
  doctor warning; its nested application repositories are indexed individually.
- Make the browse MCP opt-out per workspace (`"browse": false`) for workspaces
  that use the desktop app's built-in browser. The TUI/CLI keeps the external
  browse MCP by default.
- Do not generate automations: they are runtime state and a security decision.
  Document read-only recipes (`fefo doctor`, `fefo sync --check`) and the
  `"opencode": { "automations": false }` switch.
- Do not add an agent for image or video generation. Set a default through the
  existing `opencode` manifest block when the workspace has a media provider.
- Child orchestrators need no mandatory config change for 2.4; the browse MCP
  remains correct for the TUI. Their local Claude adapters are checked with
  `fefo adapters --check`.

Consequence: generated output shrinks for docs-only federations, doctor is clean
when the opt-outs are used, and a whitelabel workspace chooses its browser and
automation posture through the manifest instead of hand-editing generated files.

## 2026-11-27 — FEFO v2: zsh-only, OpenCode-only, CLI-only

Context: FEFO v1 carried Python, IDE adapters, slash commands, a `fefo` primary
agent, and multi-harness adapters. Session evidence showed the orchestration
method belongs in `AGENTS.md`, not in tooling, and that Python/IDE layers added
maintenance cost without value.

Decision:

- FEFO becomes a single zsh CLI. No Python, node, jq, or bash-isms in FEFO's
  own code; the only non-zsh file is `lib/vault-graph.mjs`, run by CodeGraph's
  bundled Node.
- OpenCode primary harness; basic Claude Code CLI support added (`CLAUDE.md`, `.mcp.json`,
  `.claude/skills/`); Cursor/Copilot adapters dropped.
- CLI-only: drop slash commands, modes, plugins, and the `fefo` primary agent.
  Orchestration is driven by `AGENTS.md`.
- Linux/macOS zsh only; no Windows/PowerShell paths.
- Floor raised to OpenCode 2.4.2+ (latest). Only generic 2.4.2 notes are
  documented: Esc take-back for long specs, site-scoped web-fetch approvals,
  automations surviving failed runs.
- Manifest becomes `.fefo/workspace.zsh` (line-oriented DSL, never sourced).
  Legacy `.fefo/workspace.json` is never parsed; `fefo init` keeps it as `.bak`.
- One CodeGraph MCP server (`codegraph`) with absolute `projectPath`; vault gets
  a second `vault` server served with `--no-watch`.
- Vault graph is a companion SQLite graph built from Markdown; Markdown is not a
  CodeGraph language, so it is never synced.
- Agents are either the default copied set or AI-scoped; skills kept:
  `codegraph` and `vault-search` only.
- Bonus shell functions `cmg`, `bng`, `doit` ship with fefo-install (see 2026-11-27 whitelabel decision).

Consequence: the FEFO repo shrinks to zsh + one Node helper; workspaces are
regenerated with `fefo init --force` when upgrading from Python FEFO.

## 2026-11-27 — Basic Claude Code CLI support

Context: OpenCode remains the primary harness, but users with a Claude
subscription can run Claude Code CLI directly in a FEFO workspace. Earlier
decisions dropped all Claude artifacts; the owner requested basic support.

Decision:

- When `claude on` (manifest statement, default on; `fefo init --no-claude`
  disables), `fefo sync` writes `CLAUDE.md` (two import lines plus one note),
  `.mcp.json` (mirroring every OpenCode server), and copies the two kept skills
  to `.claude/skills/`.
- No `.claude/agents`, commands, settings, or hooks are generated.
- Cursor and Copilot stay dropped.
- Doctor flags only old-FEFO wrappers (`.cursor/`, `.github/copilot-instructions.md`,
  `.claude/agents/`, `.claude/commands/`, `.claude/settings.json`), not the new
  basic Claude files.

Consequence: Claude Code CLI users get the same structure and MCP wiring;
OpenCode keeps model pinning and subagent policy.

## 2026-11-27 — FEFO is the whitelabel reference

Decision: FEFO is the whitelabel reference; installation lives only in fefo-install (downloads FEFO as a tarball, installs the CLI and the cmg/bng/doit helpers).
