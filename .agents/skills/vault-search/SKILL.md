---
name: vault-search
description: Search the FEFO graph, generated code vaults and hand-written notes for symbols, routes, decisions and source-backed evidence.
---

# Vault search

`docs/vault/` is the durable knowledge graph. `docs/vault/graph.json` indexes it together with the
generated `*-vault/` code notes. Markdown is the source of truth.

## Flow

1. `fefo vault --changed` refreshes code vaults and the FEFO graph (instant when nothing moved).
2. `fefo graph --query <term>` prints `kind | label | path:line` — start there.
3. Read `docs/vault/00-INDEX.md`; follow links to `repos/`, decisions and code vault `00-INDEX.md`.
4. For usages and callers, run `git -C <repo> grep -n` only inside the files the graph/vault names.
5. Report the note or symbol path, line and evidence.

## Rules

- No external codegraph MCP: FEFO owns the index.
- Do not present a note as current code behavior without checking the code.
- Add durable knowledge to the correct note; do not create a parallel task tracker.
- Preserve provenance: date, repository, revision and source.
