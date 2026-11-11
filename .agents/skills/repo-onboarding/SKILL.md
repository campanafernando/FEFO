---
name: repo-onboarding
description: Onboard a repository into FEFO: detect its stack, index it with CodeGraph, and fill its vault note.
---

# Repository onboarding

Use when adding a repository to a federated workspace.

## Flow

1. Confirm the Git root and the repository owner.
2. Detect the stack, package manager, test, lint, and build commands.
3. Run `./bin/fefo add <path>`.
4. Inspect `.fefo/workspace.json` and correct the role or commands when detection is wrong.
5. Run `./bin/fefo index <name>`.
6. Fill the generated `docs/vault/repos/<name>.md` domain section with:
   - responsibility
   - public entry points
   - data stores
   - external integrations
   - verification commands
7. Run `./bin/fefo doctor`.

Do not copy secrets, credentials, or personal data into the vault.
