---
name: Requirements Management
description: This skill should be used when the user asks to "list requirements", "add requirement", "create FR", "create TR", "create test requirement", "generate requirements document", "ingest requirements"
---
## Initialization (Codex)

Before using any workflow commands, call `workflow.sessionlog.bootstrap` to initialize the session log subsystem:

```yaml
type: request
payload:
  requestId: req-20260409T120000Z-bootstrap-001
  method: workflow.sessionlog.bootstrap
  params: {}
```

This is idempotent and should be called once per conversation context.


# Requirements Management

## Overview

To manage functional requirements (FR), technical requirements (TR), test requirements (TEST), and their traceability mappings, use the `workflow.requirements.*` REPL command namespace via `mcpserver-repl --agent-stdio`. All operations follow the standard YAML envelope protocol.

## Requirement ID Conventions

Three ID spaces are in use:

- **FR** — Functional Requirements: `^FR-[A-Z]+-\d{3}$`, e.g. `FR-MCP-001`, `FR-AUTH-042`
- **TR** — Technical Requirements: `^TR-[A-Z]+-[A-Z]+-\d{3}$`, e.g. `TR-MCP-ARCH-001`, `TR-AUTH-SEC-002`
- **TEST** — Test Requirements: `^TEST-[A-Z]+-\d{3}$`, e.g. `TEST-MCP-001`, `TEST-AUTH-003`

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

Mappings link an FR to one or more TRs and TESTIDs, forming the traceability matrix.

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
    trId: TR-MCP-ARCH-001
    testId: TEST-MCP-001
    notes: Core authentication flow — FR covered by ARCH constraint and unit test
```

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
      notes: Core authentication flow — FR covered by ARCH constraint and unit test
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

To generate formatted requirements documents from stored data:

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

- `functional` — numbered list of all FR entries with status and description
- `technical` — numbered list of all TR entries grouped by area/subarea
- `testing` — numbered list of all TEST entries with linked FR IDs
- `matrix` — traceability matrix table: FR × TR × TEST × status

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

## Bulk Ingestion from Markdown

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

The server parses the document, creates or updates matching FR/TR/TEST records, and returns a summary of entities created versus skipped:

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

- `requirement_not_found` — no requirement with the given ID
- `requirement_already_exists` — ID already in use; update instead of create
- `invalid_requirement_id` — ID does not match the expected regex for its type
- `mapping_not_found` — mapping between the specified FR and TR does not exist
- `invalid_mapping` — mapping references a non-existent FR, TR, or TEST ID
- `document_generation_error` — failed to render the requested document format
- `document_ingestion_error` — could not parse or persist the ingested document

## Workflow Recommendations

When discovering or agreeing on new requirements during a session:

1. Create the FR record immediately using `workflow.requirements.createFr`
2. Create the corresponding TR records using `workflow.requirements.createTr`
3. Create the TEST record using `workflow.requirements.createTest`
4. Link them with `workflow.requirements.createMapping`
5. Include the new IDs in the session log turn tags via `workflow.sessionlog.updateTurn`

Capture requirements as they emerge; do not defer to end of session. Requirements traceability is validated in CI and build failures result from missing mappings.
