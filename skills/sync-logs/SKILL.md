---
name: Sync Logs
description: Use when the user asks to "sync logs", "repair MCP session logs", "logging summary", or "summarize logging" to synchronize and reconcile MCP Server session logs through the plugin bridge.
version: 0.1.0
---

Route MCP session-log operations through your plugin's local bridge: its status check, REPL-invoke, marker-resolver, and final-response helpers (or the equivalent `ReplBridge` transport and `session*` bridge tools). Do not use raw REST for normal MCP mutations.

The `workflow.*` names below are plugin workflow/REPL method names used by the bridge, not literal agent-visible MCP tool names. Your agent-visible tools use this plugin's host-facing names, and native `/mcp-transport` tools use names such as `sessionlog_*`, `todo_*`, and `requirements_*`. Do not declare the plugin unavailable solely because generic MCP discovery does not list literal `workflow.*` names.

## Steps

1. Run a status check through the bridge first, and trust the marker details reported by the plugin.
2. Ensure session/turn handling is open with `workflow.sessionlog.openSession` or `workflow.sessionlog.beginTurn`.
3. Append reasoning and results with `workflow.sessionlog.appendDialog`.
4. Append durable actions with `workflow.sessionlog.appendActions`.
5. Discover background sessions from plugin cache/workspace session state before summarizing.
6. End with a compact factual summary that names session ids, turn ids, actions, commits, validation, defects, and unresolved blockers.

## Wrapper Result Semantics

- Treat `deprecated: true` on a successful `workflow.sessionlog.*` result as migration metadata only. It means the workflow namespace is legacy-compatible and should migrate toward `client.*` where practical; it does not mean the wrapper is broken.
- Treat only `type: error`, a nonzero wrapper exit code, `MCP_UNTRUSTED`, or `MCP_PLUGIN_UNAVAILABLE:<Agent>` as MCP/plugin failure states.
- An empty `workflow.sessionlog.queryHistory` result is a valid result. It means no sessions matched the supplied query, agent filter, workspace, or offset. Re-run the wrapper with the correct workspace current directory, explicit `agent` or `sourceType`, and plugin cache/session state before concluding history is absent.
- Do not fall back to raw REST because `queryHistory` returned no rows or because the result included `deprecated: true`. If wrapper recovery cannot find the active turn, report that sync-logs could not locate history through the plugin and continue with non-MCP work.
- Raw REST is allowed only when the user's active request is REST/API diagnostics and the plugin path has already failed closed.
