# Roadmap

## Shipped

- **v0.1** — manifest-driven generator, CodeGraph MCP per repository, modular
  agents and skills, commands, Claude/Cursor/Copilot adapters, vault scaffolding,
  `init`/`add`/`remove`/`sync`/`index`/`status`/`doctor`, MCP management.
- **v0.2** — `opencode-fefo` plugin: tools, slash commands, permission gates,
  smoke test against the current CLI.
- **v0.3** — `opencode-zshell`: `fefo`, `cmg`, `doit` and `bng`; plugin first,
  direct CLI fallback.
- **v0.5** — `fefo build` adoption and OpenCode enrichment, separate installer,
  cross-platform helpers, `sync --check`, `adapters --check`, bootstrap without
  cloning FEFO.

## v0.6 — OpenCode 2.4 and update discipline

- [x] Per-repository CodeGraph opt-out (`codegraph: false`) for docs-only
      orchestrators.
- [x] Workspace browse-MCP opt-out (`browse: false`) and browse-binary doctor
      check.
- [x] Latest-OpenCode gate in the installer, `doctor`, mutating commands, and
      the zsh helpers (cached latest-version check, CI/offline bypass).
- [x] Document the 2.4 browser, automations, media, TUI and upgrade notes.
- [x] Verify the child orchestrators and the installer, zsh, and plugin
      repositories against OpenCode 2.4.0.
- [ ] Automatic OpenCode update process (scheduled, with the same gate).
- [ ] Optional `/fefo-automation` command for the read-only `doctor` and
      `sync --check` recipes.
- [ ] Pin guidance for plugins that now auto-update by version range.
- [ ] Decide the default `external_directory` policy.

## v0.4 — knowledge graph

- [ ] Export the vault graph as JSON and Mermaid.
- [ ] Link repository notes to CodeGraph symbols and source paths.
- [ ] `fefo vault` for index and link validation.
- [ ] Optional semantic search over the vault.

## Deferred

- Remote MCP credential synchronization across harnesses.
- Multi-root CodeGraph snapshots.
- A web UI for the federation manifest.
- Automatic repository cloning from a remote manifest.
