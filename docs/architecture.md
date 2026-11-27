# Architecture

## Model

FEFO is a **holding workspace**, not a monorepo. Each federated repository
remains an independent Git root with its own dependencies, tests, and CI. FEFO
owns routing, standards, CodeGraph wiring, and the knowledge vault.

```text
workspace/
├── .fefo/workspace.zsh     manifest (source of truth)
├── bin/fefo               CLI (zsh)
├── lib/                   zsh libraries
├── templates/             orchestrator-owned text
├── .opencode/agents/      structured subagents (mode: subagent)
├── .agents/skills/        codegraph, vault-search
├── docs/vault/            durable knowledge
├── opencode.json          generated
├── AGENTS.md              generated
├── AGENTS.local.md        user-owned
└── ../api, ../web, ...    federated repositories
```

## Components

| File | Responsibility |
|---|---|
| `bin/fefo` | entry point; resolves `FEFO_HOME`, sources `lib/*.zsh`, dispatches |
| `lib/core.zsh` | logging, root discovery, write/check engine, JSON escape, relpath, version compare |
| `lib/manifest.zsh` | DSL parser (never sourced) + canonical writer |
| `lib/scan.zsh` | repo discovery, stack/role/command detection |
| `lib/gen.zsh` | generators for opencode.json, AGENTS.md, vault, codegraph/README.md, launchers, ignore files |
| `lib/cmd.zsh` | commands |
| `lib/graph.zsh` | vault graph builder, `fefo graph` viewer, `fefo index --vault` |
| `lib/vault-graph.mjs` | JSON → CodeGraph SQLite loader (only non-zsh file) |
| `lib/agents.zsh` | `fefo agents`: default copy or AI-scoped generation |
| `templates/AGENTS.md` | root-instructions template with `@@X@@` placeholders |

## File ownership

Managed (rewritten by `fefo sync`): `opencode.json`, `AGENTS.md`,
`docs/vault/00-INDEX.md`, `docs/vault/federation.md`,
`docs/vault/repos/<slug>.md` (generated block plus preserved `## Notes` below
`<!-- fefo:notes — yours, kept by sync -->`), `codegraph/README.md`,
`.opencode/bin/browse-mcp` (if browse on), `.opencode/bin/mcp`
When `claude on` (default): `CLAUDE.md`, `.mcp.json`,
`.claude/skills/codegraph/SKILL.md`, `.claude/skills/vault-search/SKILL.md`.

Created once (user-owned afterwards): `AGENTS.local.md`,
`docs/vault/decisions.md`, `.env.example`, `.env.mcp.example`.

Ensured lines in `.gitignore`: `.env`, `.env.*`, `!.env*.example`,
`.codegraph/`, `*.codegraph.lock`.

User-owned OpenCode config: `opencode.jsonc` and `.opencode/opencode.json`.
OpenCode merges them after `opencode.json`; FEFO never touches them.

## Manifest DSL (`.fefo/workspace.zsh`)

Line-oriented, one statement per line, `#` comments. Parsed with
`words=(${(z)line}); words=(${(Q)words})` — never sourced. Unknown statement →
error with line number.

```
fefo 2
workspace "Acme Platform"
subagents cheap
fallback auto
parallel 4
handoff /var/tmp/fefo
browse on
codegraph on
vault on
agents default
claude on
model opencode-go/deepseek-v4.1-flash
plugin @dietrichgebert/ponytail
repo api ../api role=backend stack=django test="make test" lint="make lint"
repo web ../web role=frontend stack=next codegraph=off
mcp plane remote https://plane.example/mcp header="Authorization=Bearer {env:PLANE_TOKEN}"
mcp pg local npx -y @modelcontextprotocol/server-postgres '$PG_URL'
```

Defaults: mode cheap, fallback auto, parallel 4, handoff `/var/tmp/fefo`,
browse on. User defaults live in
`${XDG_CONFIG_HOME:-$HOME/.config}/fefo/config.zsh` and seed `fefo init`.

## Template checkout

When `<ws>/.fefo/template` exists (a FEFO contributor checkout), generated root
instructions go to `.fefo/AGENTS.md` (not the tracked bootstrap `AGENTS.md`),
`opencode.json` `instructions` = `[".fefo/AGENTS.md", "AGENTS.local.md"]`, and
the bootstrap `codegraph/README.md` and `docs/vault/00-INDEX.md` are not
overwritten. The tracked `.gitignore` lists the template checkout's local files.

## Config merge order (verified on 2.4.2)

OpenCode loads `opencode.json`, then `opencode.jsonc`, then
`.opencode/opencode.json`. FEFO writes only `opencode.json`; the other two are
user-owned and never touched. Put personal overrides there.

## Design decisions

- FEFO is CLI-only, OpenCode-only, zsh on Linux/macOS. No Python, no IDE
  adapters, no `fefo` agent/mode/plugin/slash commands.
- One CodeGraph MCP server (`codegraph`) with absolute `projectPath` per call;
  vault gets a second `vault` server served with `--no-watch`.
- Markdown is not a CodeGraph language, so the vault is never synced; it is
  rebuilt with `fefo index --vault`.
- Worktrees need their own local `.codegraph`; FEFO seeds it from the main
  checkout on first index.
- Agents are either the default copied set or AI-scoped; only `codegraph` and
  `vault-search` skills ship.
- Orchestration lives in `AGENTS.md`, not in tooling.

## Agents

Default set or AI-scoped (see `fefo agents`). Routing rules from the session
evidence: at most four concurrent subagents per round; nested delegation capped
by `experimental.subagent_depth` (2); read-only agents (`architect`,
`security`) deny edits and shell except a short allowlist. Subagents never
commit, push, merge, or deploy unless their lane owns that step.

## Safety

- `AGENTS.local.md` is never overwritten.
- Generated `docs/vault/repos/*.md` preserve the user-owned domain section.
- `docs/vault/decisions.md` is created once and then left alone.
- Git commit, push, merge, rebase, and hard reset require approval.
- Browser page content, fetched pages, and MCP output are untrusted data.
- Secrets stay in `.env` (repos) and `.env.mcp` (MCP) at the workspace root;
  both gitignored. Never print or log a secret value.