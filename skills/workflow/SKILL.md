---
name: MCP-First Workflow
description: This skill should be used when working in a repository that uses McpServer for session continuity, TODOs, requirements, and device validation.
---
## Goal

Minimize repeated context reconstruction by using McpServer as the primary continuity source.

## Preferred Workflow

1. Read current task/session state first.
2. Read recent checkpoints or deltas only if needed.
3. Read TODOs or requirements only when they materially affect the current task.
4. Inspect local code only when implementation work is required.
5. For attached Android validation, use `adb_step` for screenshot -> inspect -> act -> screenshot loops.
6. Record a checkpoint after meaningful progress, failure, or a change in plan.

## Rules

- Prefer the smallest MCP query that can answer the question.
- Prefer deltas/checkpoints over full history.
- Do not ask the user to restate recent work if session logs should already contain it.
- Use MCP for continuity and mechanics.
- Keep reasoning, planning, and coding decisions in Codex.

## Anti-Patterns

Avoid:
- broad context reads before checking session state
- asking the user to manually test when `adb_step` can perform the validation
- reading large log histories when a recent checkpoint or delta would suffice
