# Harnesses

FEFO treats OpenCode as the canonical definition and generates adapters for the
other harnesses. Never edit a generated adapter by hand; run `./bin/fefo sync`.

## OpenCode

Reads natively:

- `opencode.json`
- `.opencode/agents/*.md`
- `.opencode/commands/*.md`
- `.agents/skills/*/SKILL.md`
- `AGENTS.md` and `AGENTS.local.md`

The generated `fefo` agent is the primary entry point. No model is pinned unless
the manifest sets `provider.model`; `opencode-go/deepseek-v4.1-flash` is the
recommendation, but any provider/model can be used. OpenCode 2.3.0+ is expected:
subagents always run in the background.

### Workspace boundary

One `opencode.json` per federation, at the father root. Child repositories carry
no harness files: no `opencode.json`, `.opencode/`, `.claude/`, `.cursor/`,
`.mcp.json`, or `CLAUDE.md`.

This works because OpenCode 2.3 merges configuration from the working directory
up through its ancestors, including the `.opencode/` and `.agents/` directories,
and because a local MCP `command` resolves from the directory of the document
that declared it. Opening `child/` therefore still loads the father's agents,
skills, commands, permissions, and MCP servers, with the father's paths intact.

The child `AGENTS.md` is the only exception, and only as a pointer: it names the
parent contract and lists conventions that are genuinely repo-local. It must not
restate routing, agents, permissions, or MCP setup.

Two caveats:

- OpenCode 2.3.1 also reads `CLAUDE.md` in any directory that has no `AGENTS.md`,
  and `~/.claude/CLAUDE.md` when there is no global `AGENTS.md`. A stray
  `CLAUDE.md` in a child is a second, uncontrolled instruction channel; keep the
  generated one at the father root only.
- Run OpenCode at the father root when a task spans repositories. The `references`
  entry gives the agent the path without changing the session directory.

## Claude Code

Generated:

- `.mcp.json` — local MCP servers, including one CodeGraph server per repository
- `.claude/agents/*.md` — wrappers that point to the canonical OpenCode agents
- `.claude/skills/<id>` — symlinks to `.agents/skills/<id>`
- `.claude/commands/*.md` — symlinks to `.opencode/commands/*.md`
- `.claude/settings.json` — Git approval rules and disabled MCP servers
- `CLAUDE.md` — imports `AGENTS.md` and `AGENTS.local.md`

Claude Code reads `CLAUDE.md` and the `.claude/` adapters. The wrappers keep the
agent body in one place, so OpenCode edits reach Claude without duplication.

Remote MCPs are included only when their headers do not use `{file:...}` or
`{env:...}`, because Claude Code cannot expand those placeholders. Configure
those servers with local-scope credentials in Claude if needed.

## Cursor

Generated `.cursor/rules/fefo.mdc` with `alwaysApply: true`. It contains the
federation table, routing summary, and critical rules. Cursor does not read
OpenCode agents or commands; the rule is the project-level fallback.

## GitHub Copilot

Generated `.github/copilot-instructions.md` with the same federation table and
rules. Copilot uses it as repository-level context. It does not load skills,
commands, or MCP servers from FEFO.

## Capability matrix

| Capability | OpenCode | Claude Code | Cursor | Copilot |
|---|---|---|---|---|
| Agents | Native | Wrappers | Routing rule | Instructions |
| Commands | Native | Symlinks | — | — |
| Skills | Native | Symlinks | — | — |
| MCP | Native | Local stdio | Manual | Manual |
| Permissions | Native | `.claude/settings.json` | Manual | Manual |
| Vault | Native | Native | Native | Native |

## Customizing generated files

Hand edits to `opencode.json` and `.claude/settings.json` are overwritten by
`sync`. Put extra settings in the manifest instead; FEFO deep-merges them
(objects merge, lists append without duplicates, `command`/`args` replace):

```jsonc
{
  "plugins": ["opencode-fefo"],
  "opencode": { "formatter": true },
  "claude_settings": { "hooks": { "Stop": [] } }
}
```

## Hand-maintained orchestrators

The Claude adapters (`.claude/agents`, `.claude/skills`, `.claude/commands`) are
derived from `.opencode/` and `.agents/skills/` and need no manifest, so the same
generator can serve a repository that maintains its own `opencode.json`:

```sh
FEFO_ROOT=/path/to/orchestrator ./bin/fefo adapters --check
FEFO_ROOT=/path/to/orchestrator ./bin/fefo adapters
```

It also checks `.mcp.json` and `disabledMcpjsonServers` against `opencode.json`
and reports drift; it never rewrites those two files.

## Sync workflow

```sh
# edit canonical sources
vim .opencode/agents/service.md

# regenerate every adapter
./bin/fefo sync

# confirm nothing is out of date (writes nothing; exit 1 on drift)
./bin/fefo sync --check

# validate
./bin/fefo doctor
```

If a harness cannot represent a feature, document the limitation here and keep
the canonical OpenCode behavior.
