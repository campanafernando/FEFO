# FEFO

FEFO is a thin federation layer for OpenCode: one zsh CLI that writes a
workspace's root instructions, OpenCode config, a markdown vault, and
CodeGraph wiring for sibling repositories. The orchestration method lives in
the generated `AGENTS.md`, so any OpenCode session in the workspace follows it
with no FEFO agent, plugin, mode, or slash command.

This checkout is the FEFO source template, not a generated workspace. Run
`fefo init` in an empty directory (with your repositories as siblings) to
create one. In this template checkout the generated root instructions live in
`.fefo/AGENTS.md`.

Read `README.md` and `docs/architecture.md` for the model and layout.