# Example manifest. Copy to .fefo/workspace.zsh and edit, or run `fefo init`.
fefo 2
workspace "Example Platform"
subagents cheap
fallback auto
parallel 4
handoff /var/tmp/fefo
browse on
codegraph on
vault on
agents default
claude on

repo api ../api role=backend stack=django test="make test" lint="make lint"
repo web ../web role=frontend stack=next codegraph=off

mcp plane remote https://plane.example/mcp header="Authorization=Bearer {env:PLANE_TOKEN}"