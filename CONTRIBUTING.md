# Contributing

FEFO is intentionally small and dependency-free. The CLI is zsh; the only
non-zsh file is `lib/vault-graph.mjs`.

## Change flow

1. Change canonical sources:
   - `lib/` for CLI behavior
   - `templates/` for orchestrator-owned text
   - `.opencode/agents/` for agents
   - `.agents/skills/` for skills
   - `docs/` for documentation
2. Run `zsh -n` on every changed `.zsh` file.
3. Run the test suite:
   ```sh
   FEFO_SKIP_UPDATE_CHECK=1 zsh tests/fefo.zsh
   ```
4. Run the generator against a temporary workspace:
   ```sh
   ./bin/fefo init --name Test --repo ../some-repo --no-index --yes
   ./bin/fefo doctor
   ./bin/fefo sync --check
   ```
5. Keep generated files in sync; never hand-edit a generated file.

## Portability rules

- Every function starts with `emulate -L zsh; setopt local_options extended_glob no_unset pipe_fail`.
- Private helpers `_fefo_*`; command entry points `_fefo_cmd_<name>`.
- No `sed -i`, `readlink -f`, `stat -c` alone, or `date -d`.
- Mtime via `zmodload -F zsh/stat b:zstat; zstat +mtime`.
- Quote every expansion; arrays as `"${arr[@]}"`.

## Adding an agent

- One responsibility per agent. Frontmatter: `description`, `mode: subagent`, no
  `model:` pin.
- Read-only agents deny `edit` and `shell` except a short allowlist.
- Add the agent to `docs/architecture.md` and the routing table in
  `templates/AGENTS.md`.

## Adding a skill

- Put it under `.agents/skills/<id>/SKILL.md`.
- Use frontmatter `name` and `description`.
- Keep it procedural and under one page.

## Style

- English documentation.
- Plain Markdown.
- No secrets, real customer data, or personal paths.
- Small, focused changes; deletion beats addition.