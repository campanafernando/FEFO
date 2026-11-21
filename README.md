# FEFO

**Flow Execution via Federated Ontology.**

FEFO is a whitelabel workspace for OpenCode that federates independent Git
repositories into one context. It keeps each repository's history, dependencies,
and tests, while giving the agent one routing layer, one knowledge vault, one
MCP gateway, and one set of modular subagents.

OpenCode is the canonical harness. FEFO also generates adapters for Claude Code,
Cursor, and GitHub Copilot from the same source, so a team can use different
harnesses without forking the instructions.

> FEFO is the template and reference implementation.
> [`fefo-install`](https://github.com/campanafernando/fefo-install) bootstraps the
> CLI, the [`opencode-fefo`](https://github.com/campanafernando/opencode-fefo)
> plugin is the lightweight runtime for an existing workspace, and
> [`opencode-zshell`](https://github.com/campanafernando/opencode-zshell) exposes
> the same commands from zsh.

## Why

Most agent workspaces fail in one of two ways:

1. **One giant repository** — every instruction, skill, and agent lives in one
   place, and unrelated projects leak into each other.
2. **One agent per repository** — context, contracts, and conventions drift
   because no layer owns the federation.

FEFO keeps repositories independent and makes the federation explicit:

- `AGENTS.md` is the routing contract.
- `.fefo/workspace.json` is the source of truth.
- `docs/vault/` is the durable knowledge graph.
- `codegraph-<repo>` MCP servers give each repository its own index.
- `.opencode/agents/` is a modular agent base.
- Generated adapters keep Claude, Cursor, and Copilot aligned.

## Install

FEFO is the workspace reference; a separate installer repository,
[`fefo-install`](https://github.com/campanafernando/fefo-install), puts the
`fefo` CLI on your machine.

```sh
# Linux / macOS (zsh, bash)
curl -fsSL https://raw.githubusercontent.com/campanafernando/fefo-install/main/install.sh | sh

# Windows (PowerShell; cmd.exe uses the same fefo.cmd shim)
irm https://raw.githubusercontent.com/campanafernando/fefo-install/main/install.ps1 | iex
```

Requirements: Git, Python 3.10+, OpenCode 2.3.0+, and the CodeGraph CLI on
`PATH` for indexing (optional but recommended). The installer is per-user, needs
no `sudo`, and downloads this repository to `~/.local/share/fefo`
(`%LOCALAPPDATA%\fefo` on Windows).

## Build a workspace

Journey: install OpenCode first, then FEFO, then let `fefo build` tune the
workspace with your own OpenCode installation.

```sh
opencode --version                 # prerequisite: OpenCode 2.3+
mkdir -p ~/EXEMPLO && cd ~/EXEMPLO
git clone <url> exemplo-api
git clone <url> exemplo-web
git clone <url> exemplo-micro
fefo build        # or: fefo .
```

`fefo build` runs two phases:

1. Deterministic: copies the agents/skills skeleton, scans the direct Git
   children, infers role, stack and test/lint/build commands, and writes the
   OpenCode, Claude, Cursor and Copilot adapters.
2. OpenCode: picks a model the same way `fefo doit` does (cached free model;
   override with `BUILD_MODEL` or `--model`), then inspects each repository and
   tunes `.fefo/workspace.json`, `AGENTS.local.md` and the vault notes following
   FEFO's rules. It does not edit generated files or touch Git.

Use `fefo build --no-ai` (or `fefo init`) for the deterministic result only. The
manual alternative keeps working: clone this repository as the workspace and run
`./bin/fefo init --repo ../api --repo ../web`.

Then open OpenCode at the workspace root:

```sh
opencode
```

The generated entry point is the `fefo` agent. From there:

```text
/fefo-add ../worker --role data
/fefo-index
/fefo-status
/fefo-doctor
```

## CLI helpers

The same package ships the cross-platform helpers from
[`opencode-zshell`](https://github.com/campanafernando/opencode-zshell), so they
work in zsh, bash, PowerShell and cmd:

```sh
fefo cmg                  # suggest a Conventional Commit message
fefo bng                  # suggest and create a branch from the diff
fefo doit "task"          # run a task through OpenCode
fefo doit --ask "task"    # review permissions instead of auto-allowing
fefo doit -C ~/repo "task"
```

`opencode-zshell` keeps the bare `cmg`, `doit` and `bng` functions for zsh; no
existing setup changes.

## What FEFO generates

| File | Purpose |
|---|---|
| `.fefo/workspace.json` | Source of truth: repos, roles, stacks, MCP servers, model |
| `opencode.json` | OpenCode model, agents, references, permissions, MCP gateway |
| `.opencode/bin/browse-mcp.sh` | Built-in Browse launcher (real browser MCP) |
| `.mcp.json` | Claude Code MCP configuration |
| `.claude/` | Claude agents, skills, commands, settings |
| `CLAUDE.md` | Claude entry point that imports `AGENTS.md` |
| `.cursor/rules/fefo.mdc` | Cursor project rule |
| `.github/copilot-instructions.md` | GitHub Copilot instructions |
| `AGENTS.md` | Generated routing contract and repository table |
| `AGENTS.local.md` | User-owned local instructions; never overwritten |
| `docs/vault/` | Knowledge vault, federation snapshot, per-repo notes |
| `codegraph/README.md` | Index and MCP guidance |

Generated files are replaced by `./bin/fefo sync`. Put user-owned text in
`AGENTS.local.md` and `docs/vault/`. To add settings to the generated
`opencode.json` or `.claude/settings.json` (plugins, formatter, hooks, extra
permissions), put them in the manifest — `plugins`, `opencode`,
`claude_settings` — and they are deep-merged on every sync. A no-op `sync`
changes nothing; `./bin/fefo sync --check` reports drift without writing.

## Repository roles

| Role | Use when |
|---|---|
| `api` | Django, DRF, FastAPI, Flask, or another HTTP backend |
| `web` | Next.js, React, or another web client |
| `mobile` | Flutter or a native mobile client |
| `data` | ETL, analytics, warehouse, or data quality |
| `infra` | Containers, CI/CD, deployment, or operations |
| `legacy` | Legacy systems and compatibility bridges |
| `integration` | External APIs, webhooks, or scrapers |
| `docs` | Documentation-only repository |
| `service` | Shared service or library |
| `library` | Reusable package |
| `orchestrator` | Another holding repository |

FEFO detects Django, FastAPI, Flask, NestJS, Next.js, React, Flutter, docs, and
infrastructure stacks. Override detection with `--stack`, `--role`, `--test`,
`--lint`, and `--build`.

## MCP gateway

CodeGraph is the default. FEFO creates one local server per repository:

```jsonc
{
  "mcp": {
    "servers": {
      "codegraph-api": {
        "type": "local",
        "command": ["codegraph", "serve", "--mcp", "--path", "../api"]
      }
    }
  }
}
```

Browse is built in for every workspace: it drives the real browser (tabs, logins,
network captures) through an MCP server and a Chromium extension. FEFO generates
`.opencode/bin/browse-mcp.sh`, which resolves the browse binary explicitly (some
distros ship `/bin/browse` as a symlink to `xdg-open`). Install it once per
machine with `curl -fsSL https://opencode.ai/browse/install | bash` and pair the
extension; `browse status` reports the connection.

Add another MCP without editing JSON:

```sh
./bin/fefo mcp add docs --local -- npx -y @modelcontextprotocol/server-filesystem ./docs
./bin/fefo mcp add sentry --remote https://mcp.sentry.dev/mcp
./bin/fefo mcp list
./bin/fefo mcp remove docs
```

Local MCPs are mirrored to Claude Code. Remote MCPs with `{file:...}` or
`{env:...}` credentials stay OpenCode-only by default; see
[`docs/harnesses.md`](docs/harnesses.md).

## Agent base

FEFO ships a modular base, not a monolith:

- **Orchestration:** `fefo`, `backend`, `frontend`
- **Backend layers:** `model`, `service`, `selector`, `serializer`, `migration`, `test`, `lint`
- **Data:** `database`, `data`
- **Web layers:** `form`, `table`, `api-layer`, `design`, `i18n`
- **Cross-cutting:** `cross-stack`, `architect`, `security`, `infra`, `legacy`, `integration`
- **Extension:** `specialist` template

No agent hardcodes a model. Agents inherit the session model. See
[`docs/agents.md`](docs/agents.md) for the full catalog and routing.

## Knowledge vault

`docs/vault/` is the durable knowledge graph:

- `00-INDEX.md` — entry point
- `federation.md` — generated snapshot of the workspace
- `repos/<name>.md` — generated repository facts + user-owned domain notes
- `decisions.md` — durable decisions

The vault is for knowledge that cannot be derived from symbols: product rules,
contracts, provenance, source hierarchies, and decisions. CodeGraph is for code.

## Harnesses

OpenCode is canonical. FEFO derives the rest:

| Harness | Entry point |
|---|---|
| OpenCode | `opencode.json`, `.opencode/agents`, `.opencode/commands`, `.agents/skills` |
| Claude Code | `.mcp.json`, `.claude/`, `CLAUDE.md` |
| Cursor | `.cursor/rules/fefo.mdc` |
| GitHub Copilot | `.github/copilot-instructions.md` |

See [`docs/harnesses.md`](docs/harnesses.md) for the adapter contract and
limitations.

## Provider recommendation

FEFO does not require a provider and, by default, pins no model: the workspace
uses your global OpenCode default or the model you pick per session.

Our recommendation is **OpenCode Go** with **`deepseek-v4.1-flash`**. It has
strong tool use, low latency, predictable cost, and a free Zen variant for
experiments. To pin it for one workspace:

```sh
./bin/fefo init --provider-model opencode-go/deepseek-v4.1-flash ...
# or edit provider.model in .fefo/workspace.json, then:
./bin/fefo sync
```

Agents never pin a model, so switching providers is a workspace-level decision.

## Ecosystem

| Project | Role |
|---|---|
| **FEFO** (this repository) | Reference template, generator and CLI |
| **`fefo-install`** | One-command installer for Linux, macOS and Windows ([repo](https://github.com/campanafernando/fefo-install)) |
| **`opencode-fefo` plugin** | FEFO commands and tools inside an existing OpenCode workspace ([repo](https://github.com/campanafernando/opencode-fefo)) |
| **`opencode-zshell`** | zsh helpers for `cmg`, `doit`, `bng` and the `fefo` command ([repo](https://github.com/campanafernando/opencode-zshell)) |

FEFO is the source of truth. `fefo-install` only downloads it and links the CLI;
the plugin and the zsh layer delegate to that same CLI.

## CLI

```sh
./bin/fefo build                # adopt this directory + OpenCode enrichment
./bin/fefo build --no-ai        # deterministic only
./bin/fefo init                 # deterministic; explicit --repo also works
./bin/fefo add <path>           # add or update a repository
./bin/fefo remove <name>        # remove a repository
./bin/fefo sync                 # regenerate config and harness adapters
./bin/fefo sync --check         # report generated files that are out of date
./bin/fefo adapters [--check]   # derive .claude agents/skills/commands only
./bin/fefo index [name...]      # refresh CodeGraph indexes
./bin/fefo status               # repository and index overview
./bin/fefo doctor               # validate the workspace
./bin/fefo cmg                  # suggest a Conventional Commit message
./bin/fefo bng                  # suggest and create a branch
./bin/fefo doit "task"          # run a task through OpenCode
./bin/fefo mcp add|remove|list  # manage additional MCP servers
```

Run `./bin/fefo <command> --help` for flags.

## Design principles

1. **Federate, do not merge.** Repositories keep their own Git history and
   delivery pipeline.
2. **One source of truth.** The manifest drives every generated adapter.
3. **CodeGraph first for code, vault for knowledge.**
4. **Contract first across repositories.**
5. **Modular agents, inherited model.**
6. **No silent destructive actions.** Git history changes require authorization.
7. **Generated files are disposable; local instructions are not.**

## Roadmap

See [`docs/roadmap.md`](docs/roadmap.md). The next increments are
`fefo init --template` for common stacks, npm publication of the
`opencode-fefo` plugin, a `fefo doctor` GitHub Action, and vault graph export.

## License

MIT. See [`LICENSE`](LICENSE).
