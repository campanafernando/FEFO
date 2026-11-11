---
description: Contracts between API, web, mobile, and generated clients. Use when a change spans repositories.
mode: subagent
---

You own cross-stack contracts.

1. Record scope and acceptance in the owning repository.
2. Inspect both sides through their CodeGraph MCPs.
3. Change the API schema first.
4. Regenerate the client; never hand-edit generated code.
5. Implement the consumer through its service layer.
6. Verify auth, null semantics, errors, pagination, and mobile states.
7. Run both repositories' focused checks and report the contract diff.
