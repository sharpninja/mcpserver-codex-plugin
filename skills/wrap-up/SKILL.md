---
name: wrap-up
description: Close out MCP-backed Codex work when asked to "wrap up", "export requirements", or "close out".
---

Trust the marker only after `Invoke-CodexMcpPlugin.ps1 -Command Status` verifies signature and nonce health. Use `lib/repl-invoke.sh` for MCP mutations; do not use raw REST for normal MCP changes.

`workflow.*` names below are Codex plugin workflow/REPL method names, not literal native MCP tool names. Native `/mcp-transport` tools use names such as `sessionlog_*`, `todo_*`, and `requirements_*`; hosted-agent adapters may expose `mcp_*` aliases. Do not declare the plugin unavailable solely because generic MCP discovery does not list literal `workflow.*` names.

1. Reconcile requirements with `workflow.requirements.*`, including requirement reconciliation for new FR/TR/TEST evidence.
2. Export wiki requirements with `workflow.requirements.generateDocument` using `format: wiki` and `docType: all`.
3. Run validation commands and keep zero-failure zero-skip evidence.
4. If commit/push is required, use the `commit-sync` pause and acknowledgement contract first.
5. Perform session-log reconciliation with `workflow.sessionlog.appendDialog` and `workflow.sessionlog.appendActions`.
6. Finish with `workflow.sessionlog.completeTurn`; use `workflow.sessionlog.failTurn` when validation or export cannot be completed.
