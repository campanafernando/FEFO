# FEFO Knowledge Vault

Durable knowledge graph for this workspace.

- `00-INDEX.md` — entry point
- `federation.md` — generated workspace snapshot
- `repos/` — generated repository facts plus user-owned domain notes
- `decisions.md` — durable decisions

Markdown is the source of truth; CodeGraph does not index it. The vault has its
own `vault` MCP server (served with `--no-watch`). Run `fefo index --vault`
after editing the vault. Run `fefo sync` after changing `.fefo/workspace.zsh`.