# Release notes

## Unreleased

- `fefo` zsh CLI: `init`, `add`, `remove`, `sync --check`, `status`, `vault`,
  `doctor`, `mcp`, `model`, `handoff`, `graph`, `agents`.
- Workspaces get the orchestration method in `AGENTS.md`, an `opencode.json`
  with `browse`, vault notes, and basic Claude Code files (`CLAUDE.md`,
  `.mcp.json`, `.claude/skills`).
- Code vaults: `fefo vault [--changed] [NAME...]` generates per-repo
  `docs/vault/<slug>-vault/` (00-INDEX, module notes, recent commits) and
  `docs/vault/graph.json`, vault-first + scoped `git grep`, `fefo vault
  --changed` at session start, both gen paths gitignored; run by `fefo init`.
- FEFO graph: `fefo graph --query <term>` finds symbols, modules, routes,
  commits and notes by label/path:line; `fefo graph` opens the local viewer.
  One zsh-built graph over code vaults and hand-written notes; no MCP server.
- Context docs: `docs/context.md`.
- Subagent model modes: cheap (strongest free model) or default (one picked
  model), always with automatic fallback.
- Installation built in: one-liner `curl -fsSL https://raw.githubusercontent.com/campanafernando/FEFO/main/install.sh | sh`, flags `--dir/--ref/--cheap/--model/--fallback/--yes/--with-all/--uninstall/--from/--ai-agents/--default-agents`, helpers cmg/bng/doit, uninstall via install.sh.
- OpenCode: latest, minimum 2.4.2. From 2.4.2: Esc returns an unsent message to
  the composer (handy for long specs); web-fetch "Always allow" is per site;
  automations keep running after a failed run.
