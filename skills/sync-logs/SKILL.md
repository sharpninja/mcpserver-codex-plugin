---
name: sync-logs
description: Synchronize MCP Server session logs for Codex when asked to "sync logs", "repair MCP session logs", or "summarize logging".
---

Use the Codex bridge path: `Invoke-CodexMcpPlugin.ps1 -Command Status`, `lib/session-start.sh`, `lib/repl-invoke.sh`, and `lib/final-response.sh`. Do not use raw REST for normal MCP mutations.

1. Run a status check and trust the marker details reported by the plugin.
2. Ensure session/turn handling is open with `workflow.sessionlog.openSession` or `workflow.sessionlog.beginTurn`.
3. Append reasoning and results with `workflow.sessionlog.appendDialog`.
4. Append durable actions with `workflow.sessionlog.appendActions`.
5. Discover background sessions from plugin cache/workspace session state before summarizing.
6. End with a compact factual summary that names sessions, turns, commits, actions, defects, and unresolved blockers.
