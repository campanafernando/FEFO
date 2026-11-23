# Decisions

Record durable decisions here with date, context, decision, and consequence.
Do not use this file as a task tracker.

## 2026-11-23 — Adopt OpenCode 2.4 in the whitelabel generator

Context: OpenCode 2.4.0 added a built-in desktop browser, automations, image and
video generation, a new TUI look, and Windows taskbar status. The generated
config still assumed the pre-2.4 browse MCP and indexed every federated
repository, including documentation-only orchestrators.

Decision:

- Require OpenCode 2.4.0+ and the latest published CLI. The installer and
  mutating `fefo` commands stop when a newer version is available;
  `FEFO_SKIP_UPDATE_CHECK=1` is limited to CI/offline use.
- Document 2.4 as the floor, not a feature tour: the docs point to the OpenCode
  release notes and enforce the version instead of repeating the changelog.
- Make CodeGraph opt-out per repository (`"codegraph": false`). A docs-only
  orchestrator should not spawn an index-less MCP server or produce a false
  doctor warning; its nested application repositories are indexed individually.
- Make the browse MCP opt-out per workspace (`"browse": false`) for workspaces
  that use the desktop app's built-in browser. The TUI/CLI keeps the external
  browse MCP by default.
- Do not generate automations: they are runtime state and a security decision.
  Document read-only recipes (`fefo doctor`, `fefo sync --check`) and the
  `"opencode": { "automations": false }` switch.
- Do not add an agent for image or video generation. Set a default through the
  existing `opencode` manifest block when the workspace has a media provider.
- Child orchestrators need no mandatory config change for 2.4; the browse MCP
  remains correct for the TUI. Their local Claude adapters are checked with
  `fefo adapters --check`.

Consequence: generated output shrinks for docs-only federations, doctor is clean
when the opt-outs are used, and a whitelabel workspace chooses its browser and
automation posture through the manifest instead of hand-editing generated files.
