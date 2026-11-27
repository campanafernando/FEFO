# CodeGraph

## What CodeGraph is

CodeGraph is a standalone CLI that indexes source code into a SQLite knowledge
graph per repository. FEFO wires one MCP server (`codegraph`) into
`opencode.json` and tells agents to pass `projectPath` (absolute path to the
repo or worktree) on every call.

Install (no Node needed):
`curl -fsSL https://raw.githubusercontent.com/colbymchenry/codegraph/main/install.sh | sh`.
Upgrade with `codegraph upgrade`.

Newer versions build the index during `codegraph init` and expose
`codegraph_explore` by default; FEFO detects `init --index` support. One
`codegraph` MCP server plus an absolute `projectPath` per call covers every
repo and worktree. Without MCP, use the CLI equivalent:
`codegraph explore "<question>" --path <dir>`.

## Why Markdown is not indexed

CodeGraph's `EXTENSION_MAP` has no `.md` entry, and its indexer skips any file
whose extension is not in that map. Even tracked Markdown files yield zero
files, zero nodes, zero edges. This is expected, not a glob or `.gitignore`
issue. The vault is therefore served by a separate `vault` MCP server built
from Markdown by FEFO (see below). `codegraph sync` on a vault graph wipes it
(confirmed): use only `fefo index --vault`. Vault parsing is pure zsh, about
0.1 s per note (a 573-note vault takes about a minute).

## Commands

```sh
fefo index                 # all codegraph-on repos
fefo index api             # one repo
fefo index api=/path/wt    # a worktree (seeds .codegraph from main checkout first)
fefo index --vault         # rebuild the vault graph
```

For a repo without FEFO: `codegraph init -i <path>` when there is no
`.codegraph/`, else `codegraph sync <path>`.

## Worktree seeding

A worktree has no `.codegraph` of its own. On first index, if the target
directory lacks `.codegraph` and its main checkout has one, FEFO copies it
(`cp -R`) before running `codegraph init`/`sync`. Worktrees must keep a local
`.codegraph`; never symlink it.

## Session-start refresh

Index staleness causes wrong answers. At the start of a session:

1. Orchestrator: `fefo index` (or `fefo index <repo>`), then `fefo status`.
2. Subagents: before edits, if `.codegraph/codegraph.db` is missing run
   `codegraph init --index <path>`; otherwise `codegraph sync <path>` for each
   touched repo/worktree. After edits, sync the same paths and report
   `projectPath`.
3. Vault: rebuild with `fefo index --vault` after vault edits; never
   `codegraph sync`.

Sync only the repos a session touches; large federations stay fast that way.
Keep the main checkout's index fresh before branching worktrees.

## Vault graph

`fefo index --vault` (needs codegraph): runs `codegraph init` on the vault when
`.codegraph` is missing, builds a JSON graph from `docs/vault/**/*.md`
(headings, wikilinks, inline/relative links, tags, repo nodes), loads it into
CodeGraph's SQLite schema (kinds mapped to module/function/variable/class), and
serves it via `codegraph serve --mcp --no-watch --path docs/vault`. Query it
with `codegraph_context`/`codegraph_search` on the `vault` server.

The loader writes nodes and edges but no `files` rows: when an MCP client
connects, CodeGraph catches up by walking `files` and deleting rows for files it
cannot parse, which would wipe every note. So `codegraph status docs/vault`
reports `Files: 0` with real symbol and edge counts — that is expected.

## know-graph viewer

`fefo graph` renders the same vault graph in a self-contained HTML page (canvas
force layout, search, kind filters, click for path/line + neighbors) and serves
it on `127.0.0.1` (default port 7737). Pure zsh; no codegraph required.
`--open` opens a browser; `--out FILE` only writes the file. Ctrl-C stops.