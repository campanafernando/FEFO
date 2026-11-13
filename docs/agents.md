# Agents

FEFO agents are modular. The orchestrator routes by domain; layer agents own one
responsibility. No agent pins a model, so the session model applies everywhere.

## Orchestration

| Agent | Mode | Responsibility |
|---|---|---|
| `fefo` | primary | Plan, route, delegate, integrate, and report |
| `backend` | subagent | Django/FastAPI/Flask orchestrator |
| `frontend` | subagent | Next.js/React/mobile orchestrator |

## Backend layers

| Agent | Responsibility |
|---|---|
| `model` | Fields, relationships, invariants, soft delete |
| `service` | Business rules, transactions, state transitions |
| `selector` | Read models, visibility, filtering, provenance |
| `serializer` | Input/output contracts, validation, schema |
| `migration` | Safe schema and data migrations |
| `test` | Focused tests and regression coverage |
| `lint` | Static analysis, formatting, pre-commit |

## Data

| Agent | Responsibility |
|---|---|
| `database` | Schema, indexes, query plans, data integrity |
| `data` | ETL, analytics, warehouses, data quality |

## Web layers

| Agent | Responsibility |
|---|---|
| `form` | Typed forms, validation, submission |
| `table` | Tables, sorting, filtering, states |
| `api-layer` | Generated SDK, server state, cache |
| `design` | Visual system, layout, accessibility |
| `i18n` | Locale keys, copy, pluralization |

## Cross-cutting

| Agent | Responsibility |
|---|---|
| `cross-stack` | API/client contracts across repositories |
| `architect` | Read-only architecture and quality review |
| `security` | Read-only security review |
| `infra` | Containers, CI/CD, deployment, operations |
| `legacy` | Legacy systems and compatibility bridges |
| `integration` | External APIs, webhooks, scrapers |

## Extension

`specialist` is a template. Copy it to `.opencode/agents/<domain>.md`, scope the
body to the domain, and add it to the routing table in `AGENTS.md` or
`AGENTS.local.md`.

```sh
cp .opencode/agents/specialist.md .opencode/agents/agriculture.md
./bin/fefo sync
```

## Routing rules

- Start with `fefo` unless the user explicitly selects an agent.
- Use one owner per file set.
- Do not delegate the same scope to two agents.
- At most four concurrent subagents per round.
- Implement the glue in the primary agent, after every report is in.
- A subagent may delegate one level only when the workspace enables
  `experimental.subagent_depth: 2`.

## Background subagents (OpenCode 2.3+)

The `subagent` tool returns immediately; the child runs in its own session and
the parent receives a report each time the child goes idle.

- Launch all independent subagents in one message.
- Never poll, sleep, or re-check a child. Continue with non-overlapping work or
  end the turn; the report arrives on its own.
- Launch a dependent layer only after its prerequisite's report has arrived.
- Reuse the child's `sessionID` to give it follow-up work.
- `opencode run` stays alive while background subagents work and exits after the parent's final answer (verified on 2.3.0).

## Read-only agents

`architect` and `security` deny `edit` and deny `shell` except a short allowlist
of read-only commands (`git diff`, `git log`, `rg`, ...), so they cannot modify
files through the shell either. In Claude Code the wrapper blocks `Edit` and
`Write`; shell restrictions are OpenCode-only, so keep review prompts explicit.
