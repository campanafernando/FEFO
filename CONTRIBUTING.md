# Contributing

FEFO is intentionally small and dependency-free. The generator is a single
Python file.

## Change flow

1. Change the canonical source:
   - `.opencode/agents/` for agents
   - `.opencode/commands/` for commands
   - `.agents/skills/` for skills
   - `tools/fefo.py` for generation behavior
   - `docs/` for documentation
2. Run the test suite:
   ```sh
   python3 -m unittest discover -s tests -v
   ```
3. Run the generator against a temporary workspace:
   ```sh
   ./bin/fefo init --name Test --repo ../some-repo --no-index --yes
   ./bin/fefo doctor
   ```
4. Regenerate adapters in the real workspace:
   ```sh
   ./bin/fefo sync
   ```
5. Keep generated files in sync; never hand-edit a generated adapter.

## Adding an agent

- One responsibility per agent.
- No hardcoded model.
- Frontmatter: `description`, `mode: subagent`.
- Read-only agents deny `edit` in `permissions`.
- Add the agent to `docs/agents.md` and the routing table in the generated
  `AGENTS.md` template inside `tools/fefo.py`.

## Adding a skill

- Put it under `.agents/skills/<id>/SKILL.md`.
- Use frontmatter `name` and `description`.
- Keep it procedural and under one page when possible.

## Adding a command

- Put it under `.opencode/commands/<name>.md`.
- Use frontmatter `description`.
- Prefer instructing the agent over embedding a shell block, unless the command
  is a deterministic wrapper around `./bin/fefo`.

## Style

- English documentation.
- Plain Markdown.
- No secrets, real customer data, or personal paths.
- Small, focused changes.
