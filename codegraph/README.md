# CodeGraph

FEFO uses one CodeGraph MCP server (`codegraph`) for every repository. Pass
`projectPath` (absolute path to the repo or worktree) on every call. FEFO does
not index Markdown: the vault is served by a separate `vault` server.

```sh
fefo index                 # all codegraph-on repos
fefo index api             # one repo
fefo index api=/path/wt   # a worktree
fefo index --vault         # rebuild the vault graph
```

Indexes live in each repository's `.codegraph/` directory and are not committed.
Worktrees need their own local `.codegraph` (FEFO seeds it from the main
checkout on first index). Refresh indexes at the start of a session before
reading code.