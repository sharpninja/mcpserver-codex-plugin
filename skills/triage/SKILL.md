---
name: Triage Reporting
description: Use when Codex discovers an incidental bug while working on another task and should submit it to MCP Server triage without changing focus.
---

# Triage Reporting

Use MCP Server triage for an incidental bug discovered while doing other work. Do not use triage for the user's active requested fix, assigned TODO, or current implementation target; fix that directly or track it through the normal TODO and requirements workflow.

Submit the report, then continue the current task. Do not expect immediate resolution, research, or TODO creation. Intake only returns the accepted queue state; background triage later groups reports, researches them, and may create a `BUG-TRIAGE-###` backlog TODO.

MCP Server-related reports, including MCP Server plugin bugs, are grouped into the registered `McpServer` workspace when that workspace exists. If no `McpServer` workspace is registered, the report stays in the submitting workspace.

## Tools

- Use `triage_report` to submit an incidental bug report.
- Use `triage_status` to inspect a report or group later.

## Report Shape

Include enough evidence for later research without leaving the active task:

- `title`: short problem statement.
- `summary`: observed failure and why it matters.
- `component`: product area, package, or plugin name.
- `affectedPaths`: relevant paths when known.
- `affectedSymbols`: relevant methods, commands, or API names when known.
- `errorSignature`: stable error text, status code, or exception type when known.
- `dedupeKey`: stable key when the same bug may be reported again.
- `evidence`: compact command output or reproduction context.

## Codex Wrapper Example

```yaml
type: request
payload:
  requestId: req-20260625T120000Z-triage-report
  method: workflow.triage.report
  params:
    title: mcpserver-codex-plugin masks method_not_found
    summary: The wrapper reports success after a workflow call fails.
    component: mcpserver-codex-plugin
    affectedPaths:
      - F:\GitHub\mcpserver-codex-plugin\lib\repl-invoke.ps1
    errorSignature: method_not_found
    reporterAgent: Codex
```

After a successful response, record the returned `reportId`, `groupId`, `status`, and `quietDeadlineUtc` only if useful for the current audit trail, then continue the current task.
