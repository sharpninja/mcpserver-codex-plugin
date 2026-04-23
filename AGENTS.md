# McpServer Codex Usage

Use the MCP Server as the default source of workspace continuity.

For ongoing work, prefer this order:

1. Read current task/session state from McpServer.
2. Read recent checkpoints or deltas from session log.
3. Read TODOs and requirements only as needed.
4. Inspect local repo files only when code must be examined or changed.
5. For attached Android validation, use `adb_step` for screenshot -> inspect -> act -> screenshot loops.
6. Record progress or failure back to session log after meaningful milestones.

Rules:
- Do not ask the user to restate recent work if it should exist in session logs.
- Prefer the smallest MCP read that can answer the question.
- Prefer checkpoint/delta reads over full-history reads.
- Use MCP for memory, logging, TODOs, requirements, and device mechanics.
- Keep reasoning and implementation decisions in Codex.
- Do not request manual device testing if `adb_step` can perform the validation.
- Do not modify unrelated code when only device validation is needed.
