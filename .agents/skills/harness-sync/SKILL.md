---
name: harness-sync
description: Regenerate and verify the Claude, Cursor, and Copilot adapters from the canonical FEFO definition.
---

# Harness sync

FEFO is canonical in OpenCode files. The other harnesses are generated.

| Harness | Generated adapter |
|---|---|
| OpenCode | `opencode.json`, `.opencode/` |
| Claude Code | `.mcp.json`, `.claude/`, `CLAUDE.md` |
| Cursor | `.cursor/rules/fefo.mdc` |
| GitHub Copilot | `.github/copilot-instructions.md` |

## Flow

1. Change `.fefo/workspace.json`, `.opencode/agents/`, `.opencode/commands/`, or `.agents/skills/`.
2. Run `./bin/fefo sync`.
3. Run `./bin/fefo doctor`.
4. Review the generated diff; never hand-edit a generated adapter.
5. Commit only after explicit authorization.

If a harness cannot represent a feature, document the limitation in
`docs/harnesses.md` and keep the canonical OpenCode behavior.
