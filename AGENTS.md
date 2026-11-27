# FEFO

FEFO is a thin federation layer for OpenCode: one zsh CLI that writes a
workspace's root instructions, OpenCode config, a markdown vault, generated
per-repo code vaults, and a FEFO graph over the vault. The orchestration method lives in
the generated `AGENTS.md`, so any OpenCode session in the workspace follows it
with no FEFO agent, plugin, mode, or slash command.

This checkout is the FEFO source, not a generated workspace (installed via
`curl -fsSL https://raw.githubusercontent.com/campanafernando/FEFO/main/install.sh | sh`, no clone;
then run `fefo init`). In this contributor checkout the generated root instructions live in
`.fefo/AGENTS.md`.

Read `README.md` and `docs/architecture.md` for the model and layout.