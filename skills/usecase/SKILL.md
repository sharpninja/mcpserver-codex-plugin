---
name: Use Case Management
description: Use when the user asks to "list use cases", "create use case", "link use case to FR", "use case diagram", "use case coverage", "approve use case", or manage use case product keys.
version: 0.1.0
---

# Use Case Management

## Overview

To manage workspace use cases, use the REPL client passthrough for `client.UseCases.*` (or MCP tools `usecase_*` on the Streamable HTTP / STDIO transport when that surface is active). Do not substitute raw REST when the plugin wrapper/REPL path is available.

Server REST base path: `/mcpserver/usecases`. Typed client: `McpServerClient.UseCases`. Plugin-core MCP tools: `usecase_*` (for hosts that load the MCP Server plugin core).

Bootstrap session log before mutations:

```yaml
type: request
payload:
  requestId: req-20260808T120000Z-bootstrap-001
  method: workflow.sessionlog.bootstrap
  params: {}
```

## List use cases

```yaml
type: request
payload:
  requestId: req-20260808T120001Z-uc-list
  method: client.UseCases.ListAsync
  params:
    title: Login
```

`title` is optional. Omit params to list all.

## Get use case

```yaml
type: request
payload:
  requestId: req-20260808T120002Z-uc-get
  method: client.UseCases.GetAsync
  params:
    useCaseId: 1
```

Detail includes `versionNumber`, `approvalStatus`, `productKey`, actors, flows, steps, and `frLinks`.

## Create use case

```yaml
type: request
payload:
  requestId: req-20260808T120003Z-uc-create
  method: client.UseCases.CreateAsync
  params:
    request:
      title: Login
      briefDescription: User authenticates
      createBasicFlow: true
      frId: FR-MCP-001
      linkType: Realizes
```

Required: `request.title`. Optional: `frId` (default link type Realizes), `createBasicFlow`.

## Update / delete

```yaml
method: client.UseCases.UpdateAsync
params:
  useCaseId: 1
  request:
    title: Login (updated)
```

```yaml
method: client.UseCases.DeleteAsync
params:
  useCaseId: 1
```

## Link / from FR

```yaml
method: client.UseCases.LinkFrAsync
params:
  useCaseId: 1
  request:
    frId: FR-MCP-001
    linkType: Realizes
```

```yaml
method: client.UseCases.CreateFromFrAsync
params:
  frId: FR-MCP-001
  request:
    title: Optional title override
```

## Diagram

```yaml
method: client.UseCases.GetDiagramAsync
params:
  useCaseId: 1
  format: mermaid
```

Supported formats: `mermaid` (primary), `plantuml`.

## Coverage (live DTO shape)

```yaml
method: client.UseCases.GetCoverageAsync
params: {}
```

Result properties (do not invent alternate names):

- `totalUseCases`, `totalFunctionalRequirements`
- `linkedUseCases`, `linkedFunctionalRequirements`
- `useCasesWithoutRealizesLink` (array of summaries)
- `functionalRequirementsWithoutRealizesUseCase` (array of FR id strings)

## Approval and product hooks

```yaml
method: client.UseCases.SetApprovalAsync
params:
  useCaseId: 1
  request:
    status: Approved
```

Statuses: `Draft`, `Submitted`, `Approved`, `Rejected`. Approving increments `versionNumber`.

```yaml
method: client.UseCases.SetProductAsync
params:
  useCaseId: 1
  request:
    productKey: prod-mcp-core
```

```yaml
method: client.UseCases.ListByProductAsync
params:
  productKey: prod-mcp-core
```

## MCP tool names (STDIO / Streamable HTTP)

When using MCP tools instead of REPL client passthrough: `usecase_list`, `usecase_get`, `usecase_create`, `usecase_update`, `usecase_delete`, `usecase_link_fr`, `usecase_from_fr`, `usecase_diagram`, `usecase_coverage`. Expanded plugin-core tools also include `usecase_set_approval`, `usecase_set_product`, `usecase_list_by_product`.

## UI

First-party UI is served at `/usecases/` on the Support.Mcp host and calls REST only.
