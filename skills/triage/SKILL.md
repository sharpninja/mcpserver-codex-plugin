---
name: Triage Reporting
description: "Use when your agent discovers an incidental bug while working on another task and should submit it to MCP Server triage without changing focus. Triggers: 'triage', '/triage', 'submit a triage report', 'report an incidental bug', 'file this bug to triage', 'triage status'."
version: 0.1.0
---

# Triage Reporting

Use MCP Server triage for an incidental bug discovered while doing other work. Do not use triage for the user's active requested fix, assigned TODO, or current implementation target; fix that directly or track it through the normal TODO and requirements workflow.

Submit the report, then continue the current task. Do not expect immediate resolution, research, or TODO creation. Intake only returns the accepted queue state; background triage later groups reports, researches them, and may create a `BUG-TRIAGE-###` backlog TODO.

MCP Server-related reports, including MCP Server plugin bugs, are grouped into the registered `McpServer` workspace when that workspace exists. If no `McpServer` workspace is registered, the report stays in the submitting workspace.

## Tools

- Use `triage_report` to submit an incidental bug report.
- Native MCP clients may use `triage_status`; plugin/REPL callers must use schema-valid `workflow.triage.getReport`, `workflow.triage.getGroup`, or `workflow.triage.queryGroups` for status inspection.

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

## REPL Example

```yaml
type: request
payload:
  requestId: req-20260625T120000Z-triage-report
  method: workflow.triage.report
  params:
    title: Plugin wrapper hides triage_report validation errors
    summary: The wrapper exits with success after a triage_report validation failure, masking the error.
    component: mcpserver-plugin
    affectedPaths:
      - lib/repl-invoke.ps1
    errorSignature: triage_validation_hidden
    reporterAgent: <your-agent>
```

After a successful response, record the returned `reportId`, `groupId`, `status`, and `quietDeadlineUtc` only if useful for the current audit trail, then continue the current task.

## PowerShell Object-Safe Example

When using the plugin PowerShell surface, prefer the exported shim helpers and `-ParamsObject` so the wrapper serializes the YAML payload:

```powershell
Import-Module (Join-Path $env:MCP_PLUGIN_ROOT 'lib/McpPluginShim.psm1') -Force
$params = New-McpTriageReportParams `
    -Title 'Plugin wrapper hides triage validation errors' `
    -Summary 'workflow.triage.report failures are not visible to the agent.' `
    -Component 'mcpserver-plugin' `
    -AffectedPaths @('lib/repl-invoke.ps1') `
    -ErrorSignature 'triage_validation_hidden' `
    -ReporterAgent '<your-agent>'
& (Join-Path $env:MCP_PLUGIN_ROOT 'lib/Invoke-McpPlugin.ps1') -Command Invoke -Method workflow.triage.report -ParamsObject $params
```

Use `New-McpTriageGetReportParams`, `New-McpTriageGetGroupParams`, and `New-McpTriageQueryGroupsParams` for object-safe status inspection through `workflow.triage.getReport`, `workflow.triage.getGroup`, and `workflow.triage.queryGroups`.
