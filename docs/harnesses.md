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

The generated `fefo` agent is the primary entry point. The default provider is
`opencode-go/deepseek-v4.1-flash`, but any provider/model can be used.

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

## Sync workflow

```sh
# edit canonical sources
vim .opencode/agents/service.md

# regenerate every adapter
./bin/fefo sync

# validate
./bin/fefo doctor
```

If a harness cannot represent a feature, document the limitation here and keep
the canonical OpenCode behavior.
