---
name: Wrap-Up
description: 'Use when asked to "wrap up", "export requirements", or "close out" MCP-backed work: reconcile MCP requirements, export wiki documents, run validation, commit and push via the commit-sync contract, reconcile the session log, and complete the turn.'
version: 0.1.0
---

Finish and synchronize MCP-backed work: reconcile requirements, export wiki documents, run validation, commit/push, and close out the session-log turn.

## Trust and transport

Trust marker details only after the plugin's local status/bootstrap check confirms marker trust and workspace health (including signature and nonce health). Use the plugin's supported wrapper surface for MCP mutations (for example `lib/repl-invoke.ps1`, or the plugin's session, todo, and requirements tools); do not use raw REST for normal MCP mutations.

## Method-name disambiguation

`workflow.*` names in this skill (`workflow.sessionlog.*`, `workflow.todo.*`, `workflow.requirements.*`) are plugin workflow/REPL method names, not literal native MCP tool names. Native `/mcp-transport` tools use names such as `sessionlog_*`, `todo_*`, and `requirements_*` (for example `sessionlog_submit`, `todo_list`, `requirements_generate`); hosted-agent adapters may expose `mcp_*` aliases. Do not declare the plugin unavailable solely because generic MCP discovery does not list literal `workflow.*` names.

If your agent exposes only a `pwsh` (or shell) tool, invoke the plugin shim directly instead of declaring it unavailable:

```
pwsh.exe -NoProfile -NonInteractive -File "<plugin-root>\lib\repl-invoke.ps1" -Method <workflow.method> -ParamsYaml <yaml>
```

## Wrap-up steps

1. Reconcile requirements with `workflow.requirements.*`, including requirement reconciliation for new FR/TR/TEST evidence.
2. Export wiki requirements with `workflow.requirements.generateDocument` using `format: wiki` and `docType: all`.
3. Run validation commands and keep zero-failure zero-skip evidence.
4. If commit/push is required, use the `commit-sync` pause and acknowledgement contract first.
5. Perform session-log reconciliation with `workflow.sessionlog.appendDialog` and `workflow.sessionlog.appendActions`.
6. Finish with `workflow.sessionlog.completeTurn`; use `workflow.sessionlog.failTurn` when validation, export, or commit/push cannot be completed (validation failure, export failure, or blocked commit/push).
