---
name: vault-search
description: Search the FEFO knowledge vault for decisions, domain rules, architecture notes, and source-backed evidence.
---

# Vault search

`docs/vault/` is the durable knowledge graph. Markdown is the source of truth.

## Flow

1. Read `docs/vault/00-INDEX.md`.
2. Open the relevant repository note under `docs/vault/repos/`.
3. Search the vault with `grep` or the editor's search for the exact term.
4. Follow links to decisions and source notes.
5. Report the note path, date, and evidence.

## Rules

- Do not use CodeGraph for Markdown; it indexes source code.
- Do not present a vault note as current code behavior without checking the code.
- Add new durable knowledge to the correct note; do not create a parallel task tracker.
- Preserve provenance: date, repository, revision, and source.
