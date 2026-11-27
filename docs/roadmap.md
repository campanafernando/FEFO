# Roadmap

## Shipped

- zsh-only CLI (`fefo`) with manifest DSL `.fefo/workspace.zsh`.
- OpenCode-first: single `opencode.json`; basic Claude Code support.
- Generated per-repo code vaults (`fefo vault`, vault-first + scoped grep;
  `--changed` session-start refresh; gitignored `docs/vault/<slug>-vault/`).
- FEFO graph (`docs/vault/graph.json`, `fefo graph --query <term>`) over code
  vaults and hand-written notes; plain-markdown knowledge vault.
- Default or AI-scoped agents; `vault-search` skill.
- `fefo handoff` protocol.

## In progress

- Test suite.
- `fefo agents --ai` non-interactive OpenCode job.
- Vault graph viewer polish.

## Planned

- Automatic OpenCode update process with the same version gate.
- Optional semantic search over the vault.
