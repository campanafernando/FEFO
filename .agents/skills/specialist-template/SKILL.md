---
name: specialist-template
description: Create a domain specialist agent from the FEFO template without hardcoding a model.
---

# Specialist template

Use when the workspace needs a domain authority that is not covered by the base agents.

## Flow

1. Copy `.opencode/agents/specialist.md` to `.opencode/agents/<domain>.md`.
2. Replace the description and body with the domain scope.
3. List the source hierarchy: workbook, policy, code, tests.
4. Define what the specialist may decide and what must be escalated.
5. Add the specialist to the routing table in `AGENTS.md` through the FEFO manifest or local instructions.
6. Run `./bin/fefo sync` and `./bin/fefo doctor`.

## Rules

- Do not hardcode a model; agents inherit the session model.
- Cite the source of each domain claim.
- Keep volatile mechanics in code and tests, not in the specialist prompt.
- Use the vault for durable domain knowledge.
