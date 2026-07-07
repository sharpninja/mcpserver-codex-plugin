---
name: Workspace Initialization
description: Use when the user asks to "initialize workspace", "register workspace", "add workspace", "create workspace marker", or "bootstrap MCP workspace"
version: 0.1.0
---

# Workspace Initialization

Initialize an MCP Server workspace only after proving whether it is already registered.

Use single-line JSON request envelopes for direct `PowerShell.MCP wrapper` stdin. JSON is valid YAML and avoids indentation/block-scalar ambiguity. When using plugin wrapper helpers such as `Invoke-McpPlugin.ps1`, pass the helper's params body exactly as documented; the wrapper validates and envelopes it. The examples here are written in YAML so folded strings, arrays, and nested request objects keep their intended shape.

## Trust Source

Prefer a trusted existing marker from the active workspace. If the target workspace already has `AGENTS-README-FIRST.yaml`, validate it with `lib/marker-resolver.ps1` before any MCP call. A trusted marker means the workspace is already registered enough to continue normal plugin bootstrap.

If the target workspace has no marker or the marker is untrusted, use another trusted control workspace marker to call the workspace lifecycle API. Do not use a marker from the untrusted target as credentials.

## Required Flow

1. Resolve the absolute target path.
2. Validate any existing target marker with `full_bootstrap <target-path>`.
3. From a trusted marker context, call `client.Workspace.ListAsync`.
4. Match `workspacePath` case-insensitively after normalizing slashes and trailing separators.
5. If no workspace matches, call `client.Workspace.CreateAsync` with a `request` object.
6. Compute the workspace key as Base64URL of the exact absolute `workspacePath`.
7. Call `client.Workspace.InitAsync` with that key.
8. Re-read and validate the target `AGENTS-README-FIRST.yaml`.
9. Only after validation succeeds, resume session log, TODO, and requirements writes through the plugin.

## PowerShell Plugin Example

Run plugin execution in PowerShell 7+ (`pwsh`). Point the plugin root at the active plugin's install directory; the wrapper reads `PLUGIN_ROOT_OVERRIDE`.

```powershell
cd F:\GitHub\McpServer
$env:PLUGIN_ROOT = 'F:\GitHub\mcpserver-<agent>-plugin'   # the active plugin's install root
$env:PLUGIN_ROOT_OVERRIDE = $env:PLUGIN_ROOT
. "$env:PLUGIN_ROOT\lib\marker-resolver.ps1"
full_bootstrap F:\GitHub\McpServer
. "$env:PLUGIN_ROOT\lib\repl-invoke.ps1"
Invoke-McpPlugin.ps1 "client.Workspace.ListAsync" ""
```

## Request Envelopes

Send the same request shape through your agent's active MCP bridge. If using the bundled REPL bridge directly for diagnosis, send one single-line JSON request object and target `client.Workspace.ListAsync`, `client.Workspace.CreateAsync`, or `client.Workspace.InitAsync`. The list call takes empty params:

```yaml
type: request
payload:
  requestId: req-20260515T115959Z-workspace-list-001
  method: client.Workspace.ListAsync
  params: {}
```

## Create If Missing

Call create only when the list result does not contain the target path.

```yaml
type: request
payload:
  requestId: req-20260515T120000Z-workspace-create-001
  method: client.Workspace.CreateAsync
  params:
    request:
      workspacePath: F:\GitHub\ExampleProject
      name: ExampleProject
      todoPath: docs/todo.yaml
      isEnabled: true
```

The equivalent `Invoke-McpPlugin.ps1` parameter body is:

```yaml
request:
  workspacePath: F:\GitHub\ExampleProject
  name: ExampleProject
  todoPath: docs/todo.yaml
  isEnabled: true
```

## Initialize Scaffold

Use the Base64URL-encoded workspace path as the key. For `F:\GitHub\ExampleProject`, encode the UTF-8 path bytes with base64, then replace `+` with `-`, `/` with `_`, and remove trailing `=`.

```yaml
type: request
payload:
  requestId: req-20260515T120001Z-workspace-init-001
  method: client.Workspace.InitAsync
  params:
    key: RjpcR2l0SHViXEV4YW1wbGVQcm9qZWN0
```

## Validation

After init, verify:

- `AGENTS-README-FIRST.yaml` exists in the target workspace root.
- `full_bootstrap <target-path>` succeeds and reports the expected workspace name and base URL.
- `client.Workspace.ListAsync` includes the target `workspacePath`.
- Session-log query and TODO query work from the target marker before any writes resume.

If any step fails, stop MCP writes for that workspace and report the exact command, response, and marker path used.
