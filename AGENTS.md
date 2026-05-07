# Agent Instructions

This file is standardized from F:\GitHub\McpServer\AGENTS.md and adjusted for this workspace.

Workspace: mcpserver-codex-plugin
Workspace root: F:\GitHub\mcpserver-codex-plugin

## Session Start

1. Check whether `AGENTS-README-FIRST.yaml` exists in this workspace root before doing anything else.
2. If the marker exists, read it and follow it exactly.
3. If the marker is absent, use the active workspace documentation, session log, TODO source, and current repository state. Do not fabricate marker availability.
4. On every user message, complete the user's request using the strongest available local continuity source.

## Rules

1. Read the marker first when it exists.
2. Complete the user's request.
3. Do not replace an explicit request with a narrower proxy unless the user approves the narrower scope.
4. Do not claim completion for work that was not done.
5. Do not claim live validation when only static inspection or partial validation was performed.
6. Keep durable work products in the workspace unless the user explicitly asks otherwise.
7. Keep handoff, TODO, session-log, and requirements artifacts current when the workspace provides them.
8. Prefer supported workspace tooling over direct file edits for TODO/session state when such tooling exists and is working.
9. Do not fabricate information. If you made a mistake, acknowledge it. Distinguish facts from speculation.
10. Prioritize correctness over speed. Do not ship code you have not verified compiles and is logically sound.
11. If instructions conflict, follow the most specific user instruction unless it would require deception, data loss, or unsafe behavior.

## Where Things Live

All relative paths are relative to F:\GitHub\mcpserver-codex-plugin unless explicitly stated otherwise.

- `AGENTS-README-FIRST.yaml` - required startup marker when present. This workspace currently has no local marker.- AGENTS.md - durable instructions that must stay aligned with the marker contract.
- .github/copilot-instructions.md - contributor/assistant instructions when present.
- docs/ - project documentation when present.
- docs/context/ - planning and context artifacts when present.
- docs/Project/ - requirements, design decisions, and project tracking when present.
- TODO.md, HANDOFF.md, session logs, or workspace MCP TODO/session-log tools - continuity artifacts when present.
- Source, test, and build layout are workspace-specific. Inspect the current repository before editing.

## MCP and Tooling

- Use workspace-provided MCP helpers, REPL tools, marker bootstrap, TODO tools, and session-log tools when present.
- Do not bypass a working supported MCP/TODO/session mechanism by directly editing backing files.
- If supported tooling fails, diagnose the tooling failure and state the fallback before using a lower-level path.
- Do not use raw HTTP/API calls where a workspace-supported helper exists unless the user explicitly asks for raw calls.

## Context Loading By Task Type

Load only the context needed for the active task, but do not omit required scope.

- Requirements or product behavior: read marker, requirements docs, design docs, TODO/session artifacts, and relevant source.
- Code changes: inspect current git status, relevant source, tests, project files, and existing patterns before editing.
- UI changes: inspect layout code, visual-tree/debug tooling if present, screenshots or reproduction evidence, and tests.
- Test work: inspect existing test conventions, failure output, coverage requirements, and any validation protocol.
- Build/release/sync work: inspect branch, remotes, status, CI docs, and current dirty tree before staging or pushing.
- Handoff or continuity work: query the current repo state and existing handoff/session artifacts before writing.

## Agent Conduct

- Be direct and factual.
- Make the actual requested change when feasible instead of only describing how to do it.
- Ask only when the answer cannot be discovered and a reasonable assumption would be risky.
- Preserve unrelated user changes.
- Stage and commit only intentional files when the user asks for git operations.
- Never revert or discard user work unless explicitly requested.
- Use concise progress updates for substantial work.

## Requirements Tracking

When a requirement is discovered, changed, or clarified:

1. Record it in the workspace's authoritative requirements or TODO system when one exists.
2. If no authoritative system exists, record it in the appropriate local planning or handoff artifact.
3. Update tests or validation sequences for behavior changes when the codebase supports tests.
4. Do not postpone requirement tracking when it is part of the current user request.

## Design Decision Logging

When making an architectural or durable design decision:

1. Record the decision in the workspace's design-decision artifact when one exists.
2. Include the reason, tradeoffs, and rejected alternatives when those details matter.
3. Keep the log factual; do not invent approvals or validation that did not happen.

## Session Continuity

Before starting significant work:

1. Inspect current git status.
2. Read active handoff/session/TODO artifacts when present.
3. Identify whether prior work is unfinished, committed, or intentionally dirty.

Before ending significant work:

1. Summarize concrete changes and verification.
2. State unverified or blocked items explicitly.
3. Update continuity artifacts when requested or required by workspace policy.

## Response Formatting

- Do not use table-style output.
- Prefer concise bullets or short paragraphs.
- Include exact paths, commands, commit IDs, build IDs, and test counts when relevant.
- If validation was not run, say so plainly.

## Workspace-Specific Notes

- This workspace supports Codex/MCP plugin continuity. Preserve session/bootstrap behavior when editing scripts or prompts.
- Verify staged-copy and live-plugin behavior when the change affects startup, handoff, or session logging.
- If no local marker exists, use the McpServer workspace contract as the continuity baseline and do not invent marker presence.
