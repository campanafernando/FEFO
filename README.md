# FEFO

**Flow Execution via Federated Ontology.**

FEFO is a whitelabel workspace for OpenCode that federates independent Git
repositories into one context. Each repository keeps its history, dependencies,
and tests; FEFO owns routing, standards, harness adapters, and the knowledge
vault.

> FEFO is the reference template and generator. `fefo-install` installs the CLI,
> the `opencode-fefo` plugin runs the same commands inside OpenCode, and
> `opencode-zshell` exposes them from zsh.

## Prerequisite: latest OpenCode

FEFO follows OpenCode. Use the latest CLI; the installer and mutating `fefo`
commands refuse to run while an update is pending.

```sh
opencode --version
opencode upgrade
```

`fefo doctor` fails when the installed CLI is older than the published latest
version. The same rule applies to the tools FEFO launches: CodeGraph, the
browser MCP, and the plugin. `FEFO_SKIP_UPDATE_CHECK=1` bypasses the check only
for CI or offline use.

Requirements: Git, Python 3.10+, OpenCode 2.4.0+ (latest). CodeGraph is optional
for indexing; the browser MCP is optional for desktop work.

## Install

Linux, macOS and WSL:

```sh
curl -fsSL https://raw.githubusercontent.com/campanafernando/fefo-install/main/install.sh | sh
```

Windows PowerShell (`cmd.exe` uses the same `fefo.cmd` shim afterwards):

```powershell
irm https://raw.githubusercontent.com/campanafernando/fefo-install/main/install.ps1 | iex
```

The installer verifies Python and the latest OpenCode, downloads FEFO to
`~/.local/share/fefo` (`%LOCALAPPDATA%\fefo` on Windows), links the `fefo` CLI,
and verifies it runs. Re-running replaces the template; workspaces keep their
own manifest, generated files and Git history.

## Build a workspace

```sh
mkdir -p ~/EXEMPLO && cd ~/EXEMPLO
git clone <url> exemplo-api
git clone <url> exemplo-web
fefo build        # or: fefo .
```

`fefo build` runs two phases:

1. Deterministic: copies the agents/skills skeleton, scans direct Git children,
   infers role, stack and commands, and writes the OpenCode, Claude, Cursor and
   Copilot adapters.
2. OpenCode: picks a model like `fefo doit` does (cached free model; override
   with `BUILD_MODEL` or `--model`), inspects each repository, and tunes
   `.fefo/workspace.json`, `AGENTS.local.md` and the vault notes. It does not
   edit generated files or run Git.

Use `fefo build --no-ai` (or `fefo init`) for the deterministic result only.
The manual alternative keeps working:

```sh
./bin/fefo init --repo ../api --repo ../web
```

Then open OpenCode at the workspace root. The generated entry point is the
`fefo` agent:

```text
/fefo-add ../worker --role data
/fefo-index
/fefo-status
/fefo-doctor
```

## CLI helpers

The same package ships cross-platform `cmg`, `bng` and `doit`:

```sh
fefo cmg                  # suggest a Conventional Commit message
fefo bng                  # suggest and create a branch from the diff
fefo doit "task"          # run a task through OpenCode
fefo doit --ask "task"    # review permissions instead of auto-allowing
fefo doit -C ~/repo "task"
```

`opencode-zshell` keeps the bare zsh functions.

## What FEFO generates

| File | Purpose |
|---|---|
| `.fefo/workspace.json` | Source of truth: repos, roles, stacks, MCP servers, model |
| `opencode.json` | OpenCode model, agents, references, permissions, MCP gateway |
| `.opencode/bin/browse-mcp.sh` | Browse launcher (omitted when `browse: false`) |
| `.mcp.json` | Claude Code MCP configuration |
| `.claude/` | Claude agents, skills, commands, settings |
| `CLAUDE.md` | Claude entry point that imports `AGENTS.md` |
| `.cursor/rules/fefo.mdc` | Cursor project rule |
| `.github/copilot-instructions.md` | GitHub Copilot instructions |
| `AGENTS.md` | Routing contract and repository table |
| `AGENTS.local.md` | User-owned local instructions; never overwritten |
| `docs/vault/` | Knowledge vault, federation snapshot, per-repo notes |
| `codegraph/README.md` | Index and MCP guidance |

Generated files are replaced by `./bin/fefo sync`. Put user-owned text in
`AGENTS.local.md` and `docs/vault/`. To add settings to the generated
`opencode.json` or `.claude/settings.json` (plugins, formatter, hooks, extra
permissions), put them in the manifest — `plugins`, `opencode`,
`claude_settings` — and they are deep-merged on every sync. A no-op `sync`
changes nothing; `./bin/fefo sync --check` reports drift without writing.

The FEFO source checkout is not a workspace: it keeps its bootstrap docs and
ignores a local generated overlay. A generated workspace gets the full set.

## Repository roles

`api`, `web`, `mobile`, `data`, `infra`, `legacy`, `integration`, `docs`,
`service`, `library`, `orchestrator`. FEFO detects Django, FastAPI, Flask,
NestJS, Next.js, React, Flutter, docs, and infrastructure stacks; override with
`--stack`, `--role`, `--test`, `--lint`, `--build`.

## MCP gateway

CodeGraph is the default. FEFO creates one local server per indexed repository:

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

Set `"codegraph": false` on a docs-only repository to skip its index and MCP
server. Set `"browse": false` in the manifest to omit the external browse MCP
and use the OpenCode desktop app's built-in browser instead. The browse MCP
remains the TUI/CLI/Claude path.

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

- **Orchestration:** `fefo`, `backend`, `frontend`
- **Backend layers:** `model`, `service`, `selector`, `serializer`, `migration`, `test`, `lint`
- **Data:** `database`, `data`
- **Web layers:** `form`, `table`, `api-layer`, `design`, `i18n`
- **Cross-cutting:** `cross-stack`, `architect`, `security`, `infra`, `legacy`, `integration`
- **Extension:** `specialist` template

No agent hardcodes a model; agents inherit the session model. See
[`docs/agents.md`](docs/agents.md) for the catalog and routing.

## Knowledge vault

`docs/vault/` stores `00-INDEX.md`, the generated `federation.md`, per-repo
`repos/<name>.md` (generated facts plus user-owned domain notes), and
`decisions.md`. CodeGraph is for code; the vault is for product rules, contracts,
provenance, and decisions.

## Harnesses

OpenCode is canonical. FEFO derives the rest:

| Harness | Entry point |
|---|---|
| OpenCode | `opencode.json`, `.opencode/agents`, `.opencode/commands`, `.agents/skills` |
| Claude Code | `.mcp.json`, `.claude/`, `CLAUDE.md` |
| Cursor | `.cursor/rules/fefo.mdc` |
| GitHub Copilot | `.github/copilot-instructions.md` |

See [`docs/harnesses.md`](docs/harnesses.md) for the adapter contract and
version policy.

## Version policy

- **Source of truth:** `https://opencode.ai/update/api/latest/cli/npm`.
- **Checked locally:** the installer, `fefo doctor`, and every mutating command.
  Read-only commands warn; writes and model turns stop until `opencode upgrade`
  has run.
- **Cached:** 24 hours in `~/.cache/opencode/latest-opencode.json`; tune with
  `FEFO_UPDATE_TTL`, or point `FEFO_UPDATE_URL` at an internal mirror.
- **Offline:** a cached version is used; without a cache the command warns and
  continues. `FEFO_SKIP_UPDATE_CHECK=1` bypasses the check for CI only.
- **Tools:** CodeGraph and browse are checked for presence; the plugin follows
  the OpenCode version. FEFO does not support pinning an older CLI.

## CLI

```sh
./bin/fefo build                # adopt this directory + OpenCode enrichment
./bin/fefo build --no-ai        # deterministic only
./bin/fefo init                 # deterministic; explicit --repo also works
./bin/fefo init --no-browse      # omit the external browse MCP
./bin/fefo add <path>            # add or update a repository
./bin/fefo add <path> --no-codegraph  # docs-only repo: no index or MCP server
./bin/fefo remove <name>         # remove a repository
./bin/fefo sync                  # regenerate config and harness adapters
./bin/fefo sync --check          # report generated files that are out of date
./bin/fefo adapters [--check]    # derive .claude agents/skills/commands only
./bin/fefo index [name...]       # refresh CodeGraph indexes
./bin/fefo status                # repository and index overview
./bin/fefo doctor                # validate the workspace and OpenCode version
./bin/fefo cmg                   # suggest a Conventional Commit message
./bin/fefo bng                   # suggest and create a branch
./bin/fefo doit "task"           # run a task through OpenCode
./bin/fefo mcp add|remove|list   # manage additional MCP servers
```

Run `./bin/fefo <command> --help` for flags.

## Ecosystem

| Project | Role |
|---|---|
| **FEFO** (this repository) | Reference template, generator and CLI |
| **`fefo-install`** | Installer for Linux, macOS and Windows |
| **`opencode-fefo`** | FEFO commands and tools inside an existing workspace |
| **`opencode-zshell`** | zsh helpers for `cmg`, `doit`, `bng` and `fefo` |

FEFO is the source of truth. The installer only downloads it and links the CLI;
the plugin and the zsh layer delegate to that same CLI.

## Design principles

1. **Federate, do not merge.** Repositories keep their own Git history and
   delivery pipeline.
2. **One source of truth.** The manifest drives every generated adapter.
3. **CodeGraph first for code, vault for knowledge.**
4. **Contract first across repositories.**
5. **Modular agents, inherited model.**
6. **No silent destructive actions.** Git history changes require authorization.
7. **Latest OpenCode, no pinned older CLI.** The installer and commands enforce
   it; the automatic updater is the next step.

## License

MIT. See [`LICENSE`](LICENSE).
