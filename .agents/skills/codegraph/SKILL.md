---
name: codegraph
description: Use the workspace's single CodeGraph MCP server for architecture, call-flow, symbol, and impact questions. Prefer it over grep for structural work.
---

# CodeGraph

FEFO exposes one `codegraph` MCP server. Pass `projectPath` (absolute path to
the repo or worktree) on every call. The server is not pinned to one repo.

## Tool selection

| Question | Tool |
|---|---|
| Where is X? | `codegraph_search` |
| How does X work? | `codegraph_explore` (default on newer CodeGraph); `codegraph_context` where offered |
| How does X reach Y? | `codegraph_trace` |
| Who calls X? | `codegraph_callers` |
| What does X call? | `codegraph_callees` |
| What breaks if X changes? | `codegraph_impact` |
| Show several related symbols | `codegraph_explore` |
| What is indexed? | `codegraph_files` |
| Is the index ready? | `codegraph_status` |

## Rules

- Run `fefo index` (or `fefo index <repo>=<path>` for a worktree) before reading code.
- Use CodeGraph before `grep`/`glob` for source structure.
- Do not reconstruct a flow that `codegraph_trace` resolves in one call.
- If the result warns about stale files, read only those files.
- CodeGraph does not index Markdown. Use the `vault` server for `docs/vault/`.
- Never pass the vault path as `projectPath` to `codegraph`.