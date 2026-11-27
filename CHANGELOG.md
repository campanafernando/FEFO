# Release notes

## Unreleased

- `fefo` zsh CLI: `init`, `add`, `remove`, `sync --check`, `status`, `index`
  (worktrees, `--vault`), `doctor`, `mcp`, `model`, `handoff`, `graph`, `agents`.
- Workspaces get the orchestration method in `AGENTS.md`, an `opencode.json` with
  one `codegraph` server plus `vault` and `browse`, vault notes, and basic Claude
  Code files (`CLAUDE.md`, `.mcp.json`, `.claude/skills`).
- Subagent model modes: cheap (strongest free model) or default (one picked
  model), always with automatic fallback.
- Installed by [fefo-install](https://github.com/campanafernando/fefo-install).
- OpenCode: latest, minimum 2.4.2. From 2.4.2: Esc returns an unsent message to
  the composer (handy for long specs); web-fetch "Always allow" is per site;
  automations keep running after a failed run.
