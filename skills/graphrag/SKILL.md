---
name: GraphRAG Knowledge Graph
description: This skill should be used when the user asks to "ingest text into graphrag", "add document to knowledge graph", "create entity", "create relationship", "query knowledge graph", "list graph entities", "delete document"
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


# GraphRAG Knowledge Graph

## Overview

To interact with the workspace GraphRAG knowledge graph, use the `workflow.graphrag.*` REPL command namespace via `mcpserver-repl --agent-stdio`. GraphRAG combines graph-based retrieval with semantic search, enabling richer context retrieval than vector-only approaches.

GraphRAG is disabled by default. Confirm it is active for the workspace before calling any operations — `workflow.graphrag.status` will report `enabled: false` if it has not been configured.

## Checking GraphRAG Status

To inspect whether GraphRAG is enabled, initialized, and indexed for the active workspace:

```yaml
type: request
payload:
  requestId: req-20260409T120000Z-status-001
  method: workflow.graphrag.status
  params: {}
```

```yaml
type: result
payload:
  requestId: req-20260409T120000Z-status-001
  result:
    enabled: true
    workspacePath: /workspace/my-project
    graphRoot: /workspace/my-project/.graphrag
    state: indexed
    isInitialized: true
    isIndexed: true
    lastIndexedAtUtc: 2026-04-09T10:00:00Z
    lastSuccessAtUtc: 2026-04-09T10:00:00Z
    lastIndexDurationMs: 4200
    lastIndexedDocumentCount: 38
    inputDocumentCount: 38
    backend: internal-fallback
```

Key `state` values: `disabled`, `uninitialized`, `idle`, `indexing`, `indexed`, `error`.

## Triggering Indexing

To rebuild the GraphRAG index from the current corpus:

```yaml
type: request
payload:
  requestId: req-20260409T120001Z-index-001
  method: workflow.graphrag.index
  params:
    force: false
```

Set `force: true` to rebuild even when no corpus changes are detected. The response reports the post-index status including whether the job was started immediately or queued.

## Querying the Knowledge Graph

To run a natural-language query against the indexed graph:

```yaml
type: request
payload:
  requestId: req-20260409T120002Z-query-001
  method: workflow.graphrag.query
  params:
    query: What authentication mechanisms does the system support?
    mode: local
    maxChunks: 10
    includeContextChunks: true
    maxEntities: 20
    maxRelationships: 20
    communityDepth: 2
    responseTokenBudget: 2000
```

Valid `mode` values:

- `local` — focuses on directly relevant entities and their immediate relationships; lower latency
- `global` — traverses community structure for broad thematic answers; higher coverage
- `drift` — follows conceptual drift to surface related but non-obvious connections

All params except `query` are optional. The result includes an `answer`, source `citations`, and optionally the raw `chunks`, `entities`, and `relationships` used:

```yaml
type: result
payload:
  requestId: req-20260409T120002Z-query-001
  result:
    query: What authentication mechanisms does the system support?
    mode: local
    answer: |
      The system supports API key authentication via the X-Api-Key header,
      workspace-scoped token rotation on server restart, and HMAC-SHA256
      marker signature verification for agent bootstrap.
    citations:
      - sourceKey: docs/MCP-SERVER.md
        chunkId: chunk-0042
        snippet: "API key authentication is required for all /mcpserver/* endpoints..."
    entities:
      - ApiKeyAuthentication
      - HmacSignatureVerification
    relationships:
      - ApiKeyAuthentication -> WorkspaceIsolation
    fallbackUsed: false
    backend: internal-fallback
```

## Ingesting Raw Text

To add a new document to the GraphRAG corpus without triggering a full reindex:

```yaml
type: request
payload:
  requestId: req-20260409T120003Z-ingest-001
  method: workflow.graphrag.ingest
  params:
    content: |
      JWT Authentication Design

      The token service uses HS256 symmetric signing with a 256-bit workspace key.
      Tokens expire after 1 hour. Refresh tokens use RS256 and expire after 30 days.
      The JwtValidator class validates token signatures and extracts claims.
    title: JWT Authentication Design
    sourceType: adhoc-text
    sourceKey: docs/jwt-auth-design
    triggerReindex: false
```

Required: `content`. Optional fields:

- `title` — human-readable document name (defaults to a generated ID if omitted)
- `sourceType` — classification tag, defaults to `adhoc-text`
- `sourceKey` — unique path/key for the document; defaults to `title` or a generated ID
- `triggerReindex` — when `true`, starts a full index rebuild after ingestion

```yaml
type: result
payload:
  requestId: req-20260409T120003Z-ingest-001
  result:
    documentId: doc-a1b2c3d4
    chunkCount: 4
    tokenCount: 312
    sourceType: adhoc-text
    sourceKey: docs/jwt-auth-design
    reindexTriggered: false
```

Store the returned `documentId` to manage the document later.

## Document Management

### Listing Documents

To browse documents in the corpus with pagination:

```yaml
type: request
payload:
  requestId: req-20260409T120004Z-doclist-001
  method: workflow.graphrag.documents.list
  params:
    skip: 0
    take: 50
    sourceType: adhoc-text
```

The `sourceType` filter is optional. The result includes `documents` (array of summaries) and `totalCount`:

```yaml
type: result
payload:
  requestId: req-20260409T120004Z-doclist-001
  result:
    documents:
      - id: doc-a1b2c3d4
        sourceType: adhoc-text
        sourceKey: docs/jwt-auth-design
        ingestedAt: 2026-04-09T12:00:03Z
        contentHash: sha256:abcdef1234...
        chunkCount: 4
        totalTokens: 312
    totalCount: 1
```

### Getting Document Chunks

To inspect the individual text chunks for a specific document:

```yaml
type: request
payload:
  requestId: req-20260409T120005Z-chunks-001
  method: workflow.graphrag.documents.chunks
  params:
    documentId: doc-a1b2c3d4
```

```yaml
type: result
payload:
  requestId: req-20260409T120005Z-chunks-001
  result:
    documentId: doc-a1b2c3d4
    chunks:
      - id: chunk-0001
        content: JWT Authentication Design. The token service uses HS256...
        tokenCount: 78
        chunkIndex: 0
      - id: chunk-0002
        content: Tokens expire after 1 hour. Refresh tokens use RS256...
        tokenCount: 82
        chunkIndex: 1
    totalChunks: 4
```

### Deleting a Document

To remove a document and all its chunks from the corpus:

```yaml
type: request
payload:
  requestId: req-20260409T120006Z-docdel-001
  method: workflow.graphrag.documents.delete
  params:
    documentId: doc-a1b2c3d4
```

```yaml
type: result
payload:
  requestId: req-20260409T120006Z-docdel-001
  result:
    documentId: doc-a1b2c3d4
    chunksRemoved: 4
    success: true
```

## Entity Management

Graph entities represent named concepts, people, organizations, or technical components extracted from or manually added to the corpus.

### Creating an Entity

```yaml
type: request
payload:
  requestId: req-20260409T120007Z-entitycreate-001
  method: workflow.graphrag.entities.create
  params:
    name: TokenService
    entityType: component
    description: Generates and signs JWT tokens using HS256 symmetric keys
    metadata: '{"project":"McpServer","layer":"services"}'
```

Required: `name`, `entityType`. Optional: `description`, `metadata` (JSON string).

```yaml
type: result
payload:
  requestId: req-20260409T120007Z-entitycreate-001
  result:
    id: ent-001
    name: TokenService
    entityType: component
    description: Generates and signs JWT tokens using HS256 symmetric keys
    createdAtUtc: 2026-04-09T12:00:07Z
    updatedAtUtc: 2026-04-09T12:00:07Z
```

### Listing Entities

```yaml
type: request
payload:
  requestId: req-20260409T120008Z-entitylist-001
  method: workflow.graphrag.entities.list
  params:
    skip: 0
    take: 50
    entityType: component
```

The `entityType` filter is optional. Returns `entities` array and `totalCount`.

### Getting a Single Entity

```yaml
type: request
payload:
  requestId: req-20260409T120009Z-entityget-001
  method: workflow.graphrag.entities.get
  params:
    entityId: ent-001
```

### Updating an Entity

```yaml
type: request
payload:
  requestId: req-20260409T120010Z-entityupdate-001
  method: workflow.graphrag.entities.update
  params:
    entityId: ent-001
    name: TokenService
    entityType: component
    description: Generates and signs JWT tokens; supports HS256 and RS256 algorithms
    metadata: '{"project":"McpServer","layer":"services","updated":true}'
```

All fields in `params` replace the existing values; supply the full entity body, not a partial patch.

### Deleting an Entity

```yaml
type: request
payload:
  requestId: req-20260409T120011Z-entitydel-001
  method: workflow.graphrag.entities.delete
  params:
    entityId: ent-001
```

Delete returns an empty result on success. Deleting an entity does not automatically remove its relationships; delete those separately first.

## Relationship Management

Relationships are directed edges between two entities with a typed label and optional weight.

### Creating a Relationship

```yaml
type: request
payload:
  requestId: req-20260409T120012Z-relcreate-001
  method: workflow.graphrag.relationships.create
  params:
    sourceEntityId: ent-001
    targetEntityId: ent-002
    relationshipType: validates
    description: TokenService uses JwtValidator to verify token signatures on refresh
    weight: 0.9
    metadata: '{"direction":"bidirectional"}'
```

Required: `sourceEntityId`, `targetEntityId`, `relationshipType`. Optional: `description`, `weight` (default `1.0`), `metadata`.

```yaml
type: result
payload:
  requestId: req-20260409T120012Z-relcreate-001
  result:
    id: rel-001
    sourceEntityId: ent-001
    targetEntityId: ent-002
    relationshipType: validates
    description: TokenService uses JwtValidator to verify token signatures on refresh
    weight: 0.9
    createdAtUtc: 2026-04-09T12:00:12Z
    updatedAtUtc: 2026-04-09T12:00:12Z
```

### Listing Relationships

```yaml
type: request
payload:
  requestId: req-20260409T120013Z-rellist-001
  method: workflow.graphrag.relationships.list
  params:
    skip: 0
    take: 50
    entityId: ent-001
    type: validates
```

Both `entityId` and `type` filters are optional. `entityId` returns all relationships where the entity appears as source or target.

### Getting a Single Relationship

```yaml
type: request
payload:
  requestId: req-20260409T120014Z-relget-001
  method: workflow.graphrag.relationships.get
  params:
    relationshipId: rel-001
```

### Updating a Relationship

```yaml
type: request
payload:
  requestId: req-20260409T120015Z-relupdate-001
  method: workflow.graphrag.relationships.update
  params:
    relationshipId: rel-001
    sourceEntityId: ent-001
    targetEntityId: ent-002
    relationshipType: validates
    description: Updated description after code review
    weight: 1.0
```

Supply the full relationship body; all fields replace existing values.

### Deleting a Relationship

```yaml
type: request
payload:
  requestId: req-20260409T120016Z-reldel-001
  method: workflow.graphrag.relationships.delete
  params:
    relationshipId: rel-001
```

## Error Handling

Common error codes for GraphRAG operations:

- `graphrag_disabled` — GraphRAG is not enabled for this workspace
- `graphrag_not_indexed` — corpus exists but has not been indexed yet; call `index` first
- `document_not_found` — no document with the specified ID
- `entity_not_found` — no entity with the specified ID
- `relationship_not_found` — no relationship with the specified ID
- `ingestion_error` — text could not be chunked or stored
- `index_error` — indexing operation failed; check status for `lastError`

## Typical Workflow

To add new knowledge and make it immediately queryable:

1. Call `workflow.graphrag.status` to verify GraphRAG is `enabled: true` and `isIndexed: true`
2. Call `workflow.graphrag.ingest` with the raw text; set `triggerReindex: false` for batch ingestion
3. Optionally call `workflow.graphrag.entities.create` to add curated entities from the text
4. Optionally call `workflow.graphrag.relationships.create` to link new entities to existing ones
5. Call `workflow.graphrag.index` with `force: false` once all documents are ingested
6. Call `workflow.graphrag.query` with `mode: local` to verify the new knowledge is retrievable

For large ingestion batches, ingest all documents first, then trigger a single `index` call at the end to minimize total indexing time.
