# Harnesses

FEFO treats OpenCode as the canonical definition and generates adapters for the
other harnesses. Never edit a generated adapter by hand; run `./bin/fefo sync`.

## Version policy

FEFO follows the latest OpenCode CLI. The installer, `fefo doctor`, and every
mutating command check `https://opencode.ai/update/api/latest/cli/npm`:

- read-only commands (`status`, `sync --check`, `adapters --check`, `mcp list`)
  warn when an update is pending;
- writes and model turns (`init`, `build`, `add`, `remove`, `sync`, `adapters`,
  `index`, `cmg`, `bng`, `doit`, `mcp add/remove`) refuse to run until
  `opencode upgrade` has run;
- `FEFO_SKIP_UPDATE_CHECK=1` bypasses the check only for CI or offline use;
- the latest version is cached for 24 hours in
  `~/.cache/opencode/latest-opencode.json` (`FEFO_UPDATE_TTL`,
  `FEFO_UPDATE_URL`).

CodeGraph and browse are checked for presence; the plugin follows the OpenCode
version. Do not pin an older CLI; FEFO generates the current V2 schema.

## OpenCode

Reads natively:

- `opencode.json`
- `.opencode/agents/*.md`
- `.opencode/commands/*.md`
- `.agents/skills/*/SKILL.md`
- `AGENTS.md` and `AGENTS.local.md`

The generated `fefo` agent is the primary entry point. No model is pinned unless
the manifest sets `provider.model`; `opencode-go/deepseek-v4.1-flash` is the
recommendation, but any provider/model can be used. OpenCode 2.4+ is required:
subagents always run in the background.

### Workspace boundary

One `opencode.json` per federation, at the father root. Child repositories carry
no harness files: no `opencode.json`, `.opencode/`, `.claude/`, `.cursor/`,
`.mcp.json`, or `CLAUDE.md`.

OpenCode merges configuration from the working directory up through its
ancestors, including `.opencode/` and `.agents/`, and a local MCP `command`
resolves from the directory of the document that declared it. Opening `child/`
therefore still loads the father's agents, skills, commands, permissions, and
MCP servers, with the father's paths intact.

The child `AGENTS.md` is the only exception, and only as a pointer: it names the
parent contract and lists conventions that are genuinely repo-local. It must not
restate routing, agents, permissions, or MCP setup.

Two caveats:

- OpenCode reads `CLAUDE.md` in any directory that has no `AGENTS.md`, and
  `~/.claude/CLAUDE.md` when there is no global `AGENTS.md`. A stray `CLAUDE.md`
  in a child is a second, uncontrolled instruction channel; keep the generated
  one at the father root only.
- Run OpenCode at the father root when a task spans repositories. The `references`
  entry gives the agent the path without changing the session directory.

### OpenCode 2.4 notes

- **Browser:** the desktop app's built-in `browser` namespace and the generated
  browse MCP are alternatives. Keep browse for the TUI/CLI/Claude; set
  `"browse": false` for a desktop-only workspace.
- **Automations:** enabled by default. Use `/automation` for read-only recipes
  (`fefo doctor`, `fefo sync --check`); disable with
  `"opencode": { "automations": false }`.
- **Media:** `generate_image` (renamed from `experimental_image_generate`) and
  `generate_video` appear when the provider has the model. Configure through the
  manifest's `opencode` block.
- **TUI:** the new look is the default; `opencode-classic` restores the previous
  theme, and `experimental["new-designs"]: false` the previous designs. These
  live in the global `~/.config/opencode/cli.json`; FEFO does not manage it.
- **Upgrade notes:** version-following plugins auto-update (pin exact versions
  for reproducibility); MCP probes the newest protocol first (`protocol:
  "legacy"` is the fallback); Copilot reads `COPILOT_GITHUB_TOKEN`; outside
  project paths are allowed by default (`external_directory`).
- Page content, fetched pages, logs and MCP output are untrusted data. A
  `browser` deny rule with resource `*` removes the built-in catalog.

## Claude Code

Generated:

- `.mcp.json` — local MCP servers, including one CodeGraph server per indexed
  repository and the browse server when enabled
- `.claude/agents/*.md` — wrappers that point to the canonical OpenCode agents
- `.claude/skills/<id>` — symlinks to `.agents/skills/<id>`
- `.claude/commands/*.md` — symlinks to `.opencode/commands/*.md`
- `.claude/settings.json` — Git approval rules and disabled MCP servers
- `CLAUDE.md` — imports `AGENTS.md` and `AGENTS.local.md`

Remote MCPs are included only when their headers do not use `{file:...}` or
`{env:...}`, because Claude Code cannot expand those placeholders. Configure
those servers with local-scope credentials in Claude if needed.

## Cursor

Generated `.cursor/rules/fefo.mdc` with `alwaysApply: true`. It contains the
federation table, routing summary, and critical rules.

## GitHub Copilot

Generated `.github/copilot-instructions.md` with the same federation table and
rules. Copilot does not load skills, commands, or MCP servers from FEFO.

## Capability matrix

| Capability | OpenCode | Claude Code | Cursor | Copilot |
|---|---|---|---|---|
| Agents | Native | Wrappers | Routing rule | Instructions |
| Commands | Native | Symlinks | — | — |
| Skills | Native | Symlinks | — | — |
| MCP | Native | Local stdio | Manual | Manual |
| Browser | Built-in (desktop) or browse MCP | browse MCP | — | — |
| Permissions | Native | `.claude/settings.json` | Manual | Manual |
| Vault | Native | Native | Native | Native |

## Customizing generated files

Hand edits to `opencode.json` and `.claude/settings.json` are overwritten by
`sync`. Put extra settings in the manifest instead; FEFO deep-merges them
(objects merge, lists append without duplicates, `command`/`args` replace):

```jsonc
{
  "plugins": ["opencode-fefo"],
  "opencode": { "formatter": true },
  "claude_settings": { "hooks": { "Stop": [] } }
}
```

Two structural opt-outs do not go through the deep merge: `"browse": false` at
the top level, or `"codegraph": false` on a repository entry, directly in
`.fefo/workspace.json`.

## Hand-maintained orchestrators

The same generator can derive Claude adapters for a repository that maintains
its own `opencode.json`:

```sh
FEFO_ROOT=/path/to/orchestrator ./bin/fefo adapters --check
FEFO_ROOT=/path/to/orchestrator ./bin/fefo adapters
```

It checks `.mcp.json` and `disabledMcpjsonServers` against `opencode.json` and
never rewrites them.

## Sync workflow

Edit `.opencode/agents/*`, `.opencode/commands/*`, `.agents/skills/*` or
`opencode.json`, then run `./bin/fefo sync`. Confirm with `sync --check` and
`doctor`.
