# Architecture

## Model

FEFO is a **holding workspace**, not a monorepo. Each federated repository
remains an independent Git root with its own dependencies, tests, and CI.

```text
workspace/
├── .fefo/workspace.json       source of truth
├── bin/fefo                   CLI
├── tools/fefo.py              generator
├── .opencode/                 canonical agents, commands
├── .agents/skills/            canonical skills
├── docs/vault/                durable knowledge
├── opencode.json              generated
├── .mcp.json                  generated
├── .claude/                   generated
├── .cursor/rules/fefo.mdc     generated
├── .github/copilot-instructions.md  generated
├── AGENTS.md                  generated
├── AGENTS.local.md            user-owned
└── ../api, ../web, ...        federated repositories
```

## Manifest

`.fefo/workspace.json` is the only input the generator needs:

```json
{
  "fefo": 1,
  "name": "My Workspace",
  "provider": { "model": null },
  "harnesses": ["opencode", "claude", "cursor", "copilot"],
  "plugins": [],
  "opencode": {},
  "claude_settings": {},
  "repos": [
    {
      "name": "api",
      "path": "../api",
      "role": "api",
      "stack": "django",
      "mcp": "codegraph-api",
      "commands": {
        "test": "python manage.py test",
        "lint": "ruff check .",
        "build": "python manage.py check"
      }
    }
  ],
  "mcp_servers": {}
}
```

FEFO validates the manifest before writing anything. Repositories are stored as
paths relative to the workspace when possible, so the checkout can move.

## Generation

```text
manifest
  ├── opencode.json       model, references, permissions, codegraph + browse MCPs
  ├── .opencode/bin/      browse MCP launcher
  ├── .mcp.json           Claude local MCPs
  ├── .claude/            agents, skills, commands, settings
  ├── CLAUDE.md           import of AGENTS.md
  ├── .cursor/rules/      project rule
  ├── .github/            Copilot instructions
  ├── AGENTS.md           routing contract and repository table
  ├── docs/vault/         index, federation snapshot, per-repo notes
  └── codegraph/          index guidance
```

`fefo sync` is idempotent. It writes a file only when the content changes, so a
no-op sync leaves the tree untouched; `fefo sync --check` lists what would change
and writes nothing. Extra settings belong in the manifest (`plugins`, `opencode`,
`claude_settings`, `mcp_servers`) and are deep-merged into the generated files.

## CodeGraph

Each repository gets its own MCP server:

```jsonc
{
  "codegraph-api": {
    "type": "local",
    "command": ["codegraph", "serve", "--mcp", "--path", "../api"]
  }
}
```

This is deliberate. A single index over unrelated repositories produces
ambiguous symbols and wrong call edges. FEFO federates at the routing layer, not
inside the index.

`fefo index`:

- creates `.codegraph/` with `codegraph init --index` when missing;
- runs `codegraph sync` when the database already exists;
- never copies an index between repositories.

## Harness adapters

OpenCode files are canonical. Adapters are derived:

| Source | Adapter |
|---|---|
| `.opencode/agents/*.md` | `.claude/agents/*.md` wrappers |
| `.agents/skills/*/SKILL.md` | `.claude/skills/<id>` symlinks |
| `.opencode/commands/*.md` | `.claude/commands/*.md` symlinks |
| `opencode.json` local MCPs | `.mcp.json` |
| `AGENTS.md` | `CLAUDE.md`, Cursor rule, Copilot instructions |

The generated Claude wrappers point back to the canonical OpenCode agent, so a
single edit reaches both harnesses.

## Safety

- `AGENTS.local.md` is never overwritten.
- Generated `docs/vault/repos/*.md` files preserve the user-owned domain section.
- `docs/vault/decisions.md` is created once and then left alone.
- Git commit, push, merge, rebase, and hard reset require approval in the
  generated OpenCode and Claude settings.
- Secrets stay in environment variables or local files, never in the manifest.

## Limits

- FEFO does not install language runtimes or repository dependencies.
- FEFO does not merge repositories or move code.
- FEFO does not create commits.
- Remote MCP credentials may be OpenCode-only; Claude Code needs local-scope
  credentials for some servers.
- Symlinked Claude skills/commands are intended for Linux, macOS, and WSL.
