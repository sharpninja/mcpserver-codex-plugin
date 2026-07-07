---
name: Requirements Management
description: Use when the user asks to "list requirements", "add requirement", "create FR", "create TR", "create test requirement", "generate requirements document", or "ingest requirements".
version: 0.1.0
---

# Requirements Management

## Overview

To manage functional requirements (FR), technical requirements (TR), test requirements (TEST), and their traceability mappings, use this plugin's declared hook/wrapper (or the REPL transport) for the `workflow.requirements.*` namespace. Do not substitute raw REST calls, generic `PowerShell.MCP wrapper`, helper modules, or another agent's plugin for normal requirements work.

The plugin wrapper validates documented params and emits single-line JSON to REPL stdio. Any direct REPL diagnostic call must use one single-line JSON request envelope, not formatted YAML.

The database is the source of truth for requirements. Markdown files are import/export projections only. Every operation is scoped to the workspace resolved from the signed marker, and generated workspace output must contain only the requested workspace's FR, TR, TEST, and traceability links.

## Initialization

Call `workflow.sessionlog.bootstrap` through this plugin's declared hook/wrapper to initialize the session log subsystem before issuing any workflow commands. This call is idempotent and should be made once per conversation context.

```yaml
type: request
payload:
  requestId: req-20260409T120000Z-bootstrap-001
  method: workflow.sessionlog.bootstrap
  params: {}
```

## Requirement Scope Layers

Plugin version 1.13.0 and newer exposes native layer operations. Treat this section as the layer API reference when plugin status reports these methods; do not ask the operator or inspect wrapper source just to learn the parameter shapes.

- `workflow.requirements.listLayers` / `req_list_layers` / `client.Requirements.ListRequirementLayersAsync`: omit params.
- `workflow.requirements.createLayer` / `req_create_layer` / `client.Requirements.CreateRequirementLayerAsync`: required params are `key`, `order`, and `name`; optional params are `description` and `scopeEndLayerKey`.
- `workflow.requirements.updateLayer` / `req_update_layer` / `client.Requirements.UpdateRequirementLayerAsync`: required param is `key`; optional params are `name`, `description`, and `scopeEndLayerKey`. Layer `order` is immutable; create a new layer rather than attempting to update `order`.
- `workflow.requirements.effective` / `req_effective` / `client.Requirements.GetEffectiveRequirementsAsync`: optional param is `layerKey`; omit `layerKey` to use the active workspace layer.

Use camelCase exactly in YAML:

```yaml
type: request
payload:
  requestId: req-20260409T115900Z-listlayers-001
  method: workflow.requirements.listLayers
  params: {}
```

```yaml
type: request
payload:
  requestId: req-20260409T115901Z-createlayer-001
  method: workflow.requirements.createLayer
  params:
    key: future
    order: 20
    name: Future Layer
    description: Requirements that are documented but not currently enforceable
```

```yaml
type: request
payload:
  requestId: req-20260409T115902Z-updatelayer-001
  method: workflow.requirements.updateLayer
  params:
    key: future
    name: Future Layer
    scopeEndLayerKey: release
```

```yaml
type: request
payload:
  requestId: req-20260409T115903Z-effective-001
  method: workflow.requirements.effective
  params:
    layerKey: future
```

FR, TR, TEST, and batch create/update commands also accept requirement scope fields:

- `scopeStartLayerKey`: first layer where the requirement is effective.
- `scopeEndLayerKey`: last layer where the requirement is effective; omit for open-ended scope.

Omit both fields for requirements that are effective in the default/current layer.

## Requirement ID Conventions

Three ID spaces are in use:

- **FR** - Functional Requirements: `^FR-[A-Z]+-\d{3}$`, e.g. `FR-MCP-001`, `FR-AUTH-042`
- **TR** - Technical Requirements: `^TR-[A-Z]+-[A-Z]+-\d{3}$`, e.g. `TR-MCP-ARCH-001`, `TR-AUTH-SEC-002`
- **TEST** - Test Requirements: `^TEST-[A-Z]+-\d{3}$`, e.g. `TEST-MCP-001`, `TEST-AUTH-003`

All IDs must be uppercase. TR IDs require both an area and a subarea segment; FR and TEST IDs require only an area segment.

## Functional Requirements (FR)

### Listing FRs

To retrieve a filtered list of functional requirements:

```yaml
type: request
payload:
  requestId: req-20260409T120000Z-listfr-001
  method: workflow.requirements.listFr
  params:
    area: MCP
    status: in_progress
```

All params are optional; omit to return all FRs. The result contains an `items` array:

```yaml
type: result
payload:
  requestId: req-20260409T120000Z-listfr-001
  result:
    items:
      - id: FR-MCP-001
        title: Agent authentication
        description: System must authenticate AI agents via API key
        status: completed
        priority: critical
        area: MCP
        createdAt: 2026-03-01T10:00:00Z
        updatedAt: 2026-04-09T12:00:00Z
    totalCount: 1
```

Valid `status` values: `pending`, `in_progress`, `completed`, `deferred`.

### Getting a Single FR

To fetch one functional requirement by ID:

```yaml
type: request
payload:
  requestId: req-20260409T120001Z-getfr-001
  method: workflow.requirements.getFr
  params:
    id: FR-MCP-001
```

### Creating an FR

To record a new functional requirement:

```yaml
type: request
payload:
  requestId: req-20260409T120002Z-createfr-001
  method: workflow.requirements.createFr
  params:
    id: FR-MCP-003
    title: Context search
    description: System must support semantic search across workspace documents
    priority: high
    area: MCP
    notes: Use hybrid search combining BM25 and vector embeddings
```

Required fields: `id`, `title`, `description`, `priority`, `area`. The `notes` field is optional.

### Acceptance Criteria

FR, TR, and TEST create/update commands accept structured `acceptanceCriteria` entries with the same shape used by TODO execution criteria:

```yaml
method: workflow.requirements.createFr
params:
  id: FR-MCP-XXX-001
  title: Acceptance criteria example
  description: Requirement records preserve structured pass/fail criteria.
  priority: high
  area: MCP
  acceptanceCriteria:
    - id: ac-1
      text: Round-trip preserves criterion text
      isSatisfied: false
    - id: ac-2
      text: Evidence is retained when supplied
      isSatisfied: true
      evidence: tests/Services/RequirementAcceptanceCriteriaTests.cs
```

To copy criteria from an execution TODO onto a requirement, call `workflow.requirements.copyAcceptanceCriteriaFromTodo`:

```yaml
method: workflow.requirements.copyAcceptanceCriteriaFromTodo
params:
  kind: fr
  id: FR-MCP-XXX-001
  todoId: PLAN-MCP-001
```

This maps to `POST /mcpserver/requirements/{kind}/{id}/acceptance-criteria/copy-from-todo` with body `{ "todoId": "PLAN-MCP-001" }`.

### Batch Create Or Update

When creating or updating multiple records, prefer the atomic batch commands instead of Markdown ingestion. Batch commands accept YAML `records:` arrays and fail all records if any record is invalid, conflicts, or is missing during update.

Use per-kind commands when every record is the same type:

```yaml
type: request
payload:
  requestId: req-20260409T120002Z-createfr-batch-001
  method: workflow.requirements.createFrBatch
  params:
    records:
      - id: FR-MCP-004
        title: Batch requirements
        description: The system must accept multiple requirement records in one request.
        priority: high
      - id: FR-MCP-005
        title: Atomic validation
        description: The system must reject the whole batch when one record is invalid.
        priority: high
```

Use `workflow.requirements.updateFrBatch`, `createTrBatch`, `updateTrBatch`, `createTestBatch`, and `updateTestBatch` for per-kind batches. For mixed FR/TR/TEST arrays, use `workflow.requirements.createBatch` or `workflow.requirements.updateBatch` and include `kind: fr|tr|test` on each record.

### Updating an FR

To modify an existing FR:

```yaml
type: request
payload:
  requestId: req-20260409T120003Z-updatefr-001
  method: workflow.requirements.updateFr
  params:
    id: FR-MCP-003
    status: completed
    notes: Implemented with HybridSearchService using all-MiniLM-L6-v2 embeddings
```

### Deleting an FR

```yaml
type: request
payload:
  requestId: req-20260409T120004Z-deletefr-001
  method: workflow.requirements.deleteFr
  params:
    id: FR-MCP-003
```

## Technical Requirements (TR)

TR IDs require both `area` and `subarea` segments. The full ID format is `TR-<AREA>-<SUBAREA>-###`.

### Listing TRs

```yaml
type: request
payload:
  requestId: req-20260409T120005Z-listtr-001
  method: workflow.requirements.listTr
  params:
    area: MCP
    subarea: PERF
```

### Creating a TR

```yaml
type: request
payload:
  requestId: req-20260409T120006Z-createtr-001
  method: workflow.requirements.createTr
  params:
    id: TR-MCP-PERF-001
    title: API response time SLA
    description: All API endpoints must respond within 500ms at p99
    priority: high
    area: MCP
    subarea: PERF
    notes: Measured at gateway, excluding network transit time
```

### Updating a TR

```yaml
type: request
payload:
  requestId: req-20260409T120007Z-updatetr-001
  method: workflow.requirements.updateTr
  params:
    id: TR-MCP-PERF-001
    status: in_progress
    notes: Baseline established at 320ms p99 under load test
```

### Deleting a TR

```yaml
type: request
payload:
  requestId: req-20260409T120008Z-deletetr-001
  method: workflow.requirements.deleteTr
  params:
    id: TR-MCP-PERF-001
```

## Test Requirements (TEST)

### Listing TEST Requirements

```yaml
type: request
payload:
  requestId: req-20260409T120009Z-listtest-001
  method: workflow.requirements.listTest
  params:
    area: MCP
```

### Creating a TEST Requirement

```yaml
type: request
payload:
  requestId: req-20260409T120010Z-createtest-001
  method: workflow.requirements.createTest
  params:
    id: TEST-MCP-001
    title: Agent authentication unit test
    description: Verify API key authentication rejects invalid tokens with 401
    priority: critical
    area: MCP
    notes: Uses in-memory EF provider with CustomWebApplicationFactory
```

### Updating and Deleting TEST Requirements

Follow the same pattern as FR: use `workflow.requirements.updateTest` and `workflow.requirements.deleteTest` with the same parameter shapes.

## Requirement Mappings

Mappings link an FR to one or more TRs and TEST IDs in the current workspace, forming the traceability matrix.

### Listing Mappings

```yaml
type: request
payload:
  requestId: req-20260409T120011Z-listmap-001
  method: workflow.requirements.listMappings
  params:
    frId: FR-MCP-001
```

### Creating a Mapping

```yaml
type: request
payload:
  requestId: req-20260409T120012Z-createmap-001
  method: workflow.requirements.createMapping
  params:
    frId: FR-MCP-001
    trIds:
      - TR-MCP-ARCH-001
    testIds:
      - TEST-MCP-001
    notes: Core authentication flow covered by ARCH constraint and unit test
```

Legacy single-link `trId` and `testId` inputs are accepted for compatibility. Prefer `trIds` and `testIds` for all new calls.

The result confirms the stored mapping:

```yaml
type: result
payload:
  requestId: req-20260409T120012Z-createmap-001
  result:
    item:
      frId: FR-MCP-001
      trId: TR-MCP-ARCH-001
      testId: TEST-MCP-001
      createdAt: 2026-04-09T12:00:12Z
      notes: Core authentication flow covered by ARCH constraint and unit test
```

### Deleting a Mapping

```yaml
type: request
payload:
  requestId: req-20260409T120013Z-deletemap-001
  method: workflow.requirements.deleteMapping
  params:
    frId: FR-MCP-001
    trId: TR-MCP-ARCH-001
```

## Document Generation

To generate formatted requirements documents from the current workspace database slice:

```yaml
type: request
payload:
  requestId: req-20260409T120014Z-gendoc-001
  method: workflow.requirements.generateDocument
  params:
    format: markdown
    docType: matrix
```

Valid `docType` values:

- `functional` - numbered list of all FR entries with status and description
- `technical` - numbered list of all TR entries grouped by area/subarea
- `testing` - numbered list of all TEST entries with linked FR IDs
- `matrix` - traceability matrix table: FR × TR × TEST × status
- `all` - complete export package

```yaml
type: result
payload:
  requestId: req-20260409T120014Z-gendoc-001
  result:
    content: |
      # Requirement Traceability Matrix

      | FR ID      | TR ID           | TEST ID      | Status |
      |------------|-----------------|--------------|--------|
      | FR-MCP-001 | TR-MCP-ARCH-001 | TEST-MCP-001 | done   |
      | FR-MCP-002 | TR-MCP-ARCH-002 | TEST-MCP-003 | open   |
    format: markdown
    docType: matrix
    generatedAt: 2026-04-09T12:00:14Z
```

### Wiki Export

Use `format: wiki` with `docType: all` to export wiki files directly into the workspace. The normal result returns metadata, not archive bytes. Files are written under `docs/Project/wiki/azure` and `docs/Project/wiki/github`. Each folder includes `.mcp-requirements-manifest.json`; Azure also includes `.order`; GitHub also includes `_Sidebar.md` and `_Footer.md`. When an older REPL cannot serialize the metadata result, the wrapper may return `contentBase64` with `contentType: application/json`; decode it to read the same export metadata.

```yaml
type: request
payload:
  requestId: req-20260409T120014Z-gendoc-wiki-001
  method: workflow.requirements.generateDocument
  params:
    format: wiki
    docType: all
```

```yaml
type: result
payload:
  requestId: req-20260409T120014Z-gendoc-wiki-001
  result:
    format: wiki
    docType: all
    generatedAtUtc: 2026-04-09T12:00:14Z
    outputRoot: F:\GitHub\McpServer\docs\Project\wiki
    files:
      - relativePath: azure/Home.md
        fullPath: F:\GitHub\McpServer\docs\Project\wiki\azure\Home.md
        contentType: text/markdown
        lastModifiedUtc: 2026-04-09T12:00:14Z
```

## Bulk Ingestion

To import requirements from an existing Markdown document:

```yaml
type: request
payload:
  requestId: req-20260409T120015Z-ingest-001
  method: workflow.requirements.ingestDocument
  params:
    content: |
      ## FR-MCP-010: GraphRAG ingestion
      The system must support ingestion of raw text into the GraphRAG corpus.
      Priority: high | Area: MCP | Status: pending

      ## TR-MCP-GRAPH-001: Chunked text embedding
      Ingested text must be split into chunks and embedded using all-MiniLM-L6-v2.
      Priority: high | Area: MCP | Subarea: GRAPH | Status: pending
    format: markdown
```

To import wiki documents, pass a path-keyed `documents` map and include `lastModifiedUtc` per entry when available. Use `sourceFormat: auto` or `wiki`; set `preferredWikiFormat: azure|github` only when the Azure and GitHub timestamp checks disagree. The server compares both `.mcp-requirements-manifest.json` `generatedAtUtc` values and the latest `lastModifiedUtc` per platform. If both checks agree, the newer platform is selected. If they disagree and no preference is supplied, import fails. The selected platform folder is authoritative: missing records are deleted, changed records are updated, new records are created, and identical records are ignored.

```yaml
type: request
payload:
  requestId: req-20260409T120015Z-ingest-wiki-001
  method: workflow.requirements.ingestDocument
  params:
    format: wiki
    sourceFormat: wiki
    preferredWikiFormat: github
    documents:
      github/.mcp-requirements-manifest.json:
        content: '{"generatedAtUtc":"2026-04-09T12:00:14Z"}'
        lastModifiedUtc: 2026-04-09T12:00:14Z
      github/Functional-Requirements.md:
        content: |
          # Functional Requirements (MCP Server)
        lastModifiedUtc: 2026-04-09T12:00:15Z
```

The server parses the document, creates, updates, deletes, or ignores matching FR/TR/TEST/mapping records, and returns a summary:

```yaml
type: result
payload:
  requestId: req-20260409T120015Z-ingest-001
  result:
    created: 2
    updated: 0
    skipped: 0
    errors: []
```

## Error Handling

Common error codes:

- `requirement_not_found` - no requirement with the given ID
- `requirement_already_exists` - ID already in use; update instead of create
- `invalid_requirement_id` - ID does not match the expected regex for its type
- `mapping_not_found` - mapping between the specified FR and TR does not exist
- `invalid_mapping` - mapping references a non-existent FR, TR, or TEST ID
- `document_generation_error` - failed to render the requested document format
- `document_ingestion_error` - could not parse or persist the ingested document

## Workflow Recommendations

When discovering or agreeing on new requirements during a session:

1. Create the FR record immediately using `workflow.requirements.createFr`
2. Create the corresponding TR records using `workflow.requirements.createTr`
3. Create the TEST record using `workflow.requirements.createTest`
4. Link them with `workflow.requirements.createMapping`
5. Include the new IDs in the session log turn tags via `workflow.sessionlog.updateTurn`

Capture requirements as they emerge; do not defer to end of session. Requirements traceability is validated in CI and build failures result from missing mappings.
