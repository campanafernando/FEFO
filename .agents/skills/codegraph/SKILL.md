---
name: codegraph
description: Use the repository's CodeGraph MCP for architecture, call-flow, symbol, and impact questions. Prefer it over grep for structural work.
---

# CodeGraph

Use the federated `codegraph-<repository>` server for the repository that owns the question.

## Tool selection

| Question | Tool |
|---|---|
| Where is X? | `codegraph_search` |
| How does X work? | `codegraph_context` |
| How does X reach Y? | `codegraph_trace` |
| Who calls X? | `codegraph_callers` |
| What does X call? | `codegraph_callees` |
| What breaks if X changes? | `codegraph_impact` |
| Show several related symbols | `codegraph_explore` |
| What is indexed? | `codegraph_files` |
| Is the index ready? | `codegraph_status` |

## Rules

- Use CodeGraph before `grep`/`glob` for source structure.
- Do not reconstruct a flow that `codegraph_trace` resolves in one call.
- If the result warns about stale files, read only those files.
- Refresh indexes with `./bin/fefo index <repository>` after source changes.
- CodeGraph does not index Markdown knowledge; use `docs/vault/` for that.
