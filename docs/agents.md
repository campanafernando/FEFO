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
- Implement the glue in the primary agent.
- A subagent may delegate one level only when the workspace enables
  `experimental.subagent_depth: 2`.
