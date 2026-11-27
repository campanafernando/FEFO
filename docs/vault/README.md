# FEFO Knowledge Vault

Durable knowledge for this workspace.

- `00-INDEX.md` — entry point
- `federation.md` — generated workspace snapshot
- `repos/` — generated repository facts plus user-owned domain notes
- `decisions.md` — durable decisions
- `<slug>-vault/` — generated per-repo code vaults (`fefo vault`, gitignored;
  never edit by hand; not knowledge notes)

Markdown is the source of truth; `graph.json` is built from it by `fefo vault`.
`fefo graph --query <term>` searches it; `fefo graph` renders it. Run
`fefo sync` after changing `.fefo/workspace.zsh`. Code vaults and the graph
refresh with `fefo vault [--changed]`.
