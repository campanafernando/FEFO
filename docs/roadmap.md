# Roadmap

## v0.1 — workspace foundation

- [x] Manifest-driven workspace generator
- [x] CodeGraph MCP per federated repository
- [x] Modular agent base and skills
- [x] OpenCode commands
- [x] Claude, Cursor, and Copilot adapters
- [x] Vault scaffolding and repository notes
- [x] `init`, `add`, `remove`, `sync`, `index`, `status`, `doctor`
- [x] MCP add/remove/list

## v0.2 — OpenCode plugin

- [x] Separate `opencode-fefo` plugin repository scaffold
- [x] Register `fefo` tools and slash commands inside OpenCode
- [x] Delegate to the workspace CLI without duplicating the generator
- [ ] Bootstrap instructions for workspaces without the FEFO template
- [ ] Plugin smoke test against OpenCode 2.3.0+ (unit tests only so far)
- [ ] Publish the plugin to npm

## v0.3 — opencode-zshell integration

- [x] Update `opencode-zshell` to call the `opencode-fefo` plugin
- [x] Add a zsh `fefo` helper with status, add, sync, index, and doctor
- [x] Keep a direct CLI fallback when the plugin is unavailable
- [x] Document the three layers: FEFO template, plugin, zshell

## v0.4 — knowledge graph

- [ ] Export the vault graph as JSON and Mermaid
- [ ] Link repository notes to CodeGraph symbols and source paths
- [ ] Add a `fefo vault` command for index and link validation
- [ ] Optional semantic search over the vault

## v0.5 — delivery

- [ ] `fefo init --template` for common stacks
- [ ] Workspace bootstrap without cloning FEFO
- [x] `fefo sync --check`, `fefo adapters --check` and a wider `fefo doctor`
- [ ] GitHub Action that runs `fefo doctor` and `fefo sync --check`
- [ ] Plugin published to npm
- [ ] FEFO template published as a GitHub template repository

## Deferred

- Remote MCP credential synchronization across harnesses
- Multi-root CodeGraph snapshots
- A web UI for the federation manifest
- Automatic repository cloning from a remote manifest
