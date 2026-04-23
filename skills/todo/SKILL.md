---
name: TODO Management
description: This skill should be used when the user asks to "create a todo", "list todos", "update todo", "query tasks", "check todo status", "plan implementation", "mark todo done"
---
## Initialization (Codex)

All `workflow.todo.*` examples in this skill are intended for
`lib/repl-invoke.sh`, which translates supported calls to the real `client.*`
methods exposed by `mcpserver-repl`. The current wrapper supports CRUD,
querying, requirements analysis, and selected-TODO state; the streaming prompt
verbs described later are not exposed in this Codex wrapper.

Before using any workflow commands, call `workflow.sessionlog.bootstrap` to initialize the session log subsystem:

```yaml
type: request
payload:
  requestId: req-20260409T120000Z-bootstrap-001
  method: workflow.sessionlog.bootstrap
  params: {}
```

This is idempotent and should be called once per conversation context.


# TODO Management

## Overview

To interact with project TODOs, use the `workflow.todo.*` namespace through
`lib/repl-invoke.sh`. All commands follow the standard YAML envelope protocol:
send a `type: request` envelope on stdin, receive a `type: result` or
`type: error` envelope on stdout.

## TODO ID Naming Conventions

Persist only IDs that conform to one of two patterns:

- `^[A-Z]+-[A-Z0-9]+-\d{3}$` — three-segment uppercase kebab-case, e.g. `PLAN-NAMINGCONVENTIONS-001`, `MCP-AUTH-042`
- `^ISSUE-\d+$` — GitHub-backed canonical ID, e.g. `ISSUE-17`

The special create-only value `ISSUE-NEW` instructs the server to create a GitHub issue, rewrite the stored ID to `ISSUE-{number}`, and return the canonical form. After the first sync, the `description` / `body` of an `ISSUE-{number}` TODO is immutable from the server side; subsequent update calls surface the change as a GitHub issue comment instead of overwriting the body.

When populating `dependsOn`, each dependency ID must also conform to these patterns.

## Querying TODOs

To retrieve a filtered list of TODOs:

```yaml
type: request
payload:
  requestId: req-20260409T120000Z-query-001
  method: workflow.todo.query
  params:
    keyword: authentication
    priority: high
    section: Backend
    done: false
```

All `params` fields are optional. Omit `params` entirely to return all TODOs. The response contains a paginated `items` array:

```yaml
type: result
payload:
  requestId: req-20260409T120000Z-query-001
  result:
    items:
      - id: MCP-AUTH-001
        title: Implement JWT authentication
        section: Backend
        priority: high
        done: false
        estimate: 4h
        functionalRequirements: [FR-AUTH-001]
        technicalRequirements: [TR-AUTH-001]
    totalCount: 1
```

Valid `priority` values: `critical`, `high`, `medium`, `low`.

## Getting a Single TODO

To fetch the full detail of one TODO by ID:

```yaml
type: request
payload:
  requestId: req-20260409T120001Z-get-001
  method: workflow.todo.get
  params:
    id: MCP-AUTH-001
```

The result includes all fields: `implementationTasks`, `description`, `technicalDetails`, `remaining`, `doneSummary`, `dependsOn`, requirement arrays, and timestamps.

## Selecting a TODO as Active Context

To set a TODO as the active working context for the session:

```yaml
type: request
payload:
  requestId: req-20260409T120002Z-select-001
  method: workflow.todo.select
  params:
    id: MCP-AUTH-001
```

Once selected, `workflow.todo.updateSelected` may be used to patch fields without repeating the ID on every call.

## Creating a TODO

To create a new project task:

```yaml
type: request
payload:
  requestId: req-20260409T120003Z-create-001
  method: workflow.todo.create
  params:
    id: MCP-AUTH-002
    title: Add rate limiting to auth endpoints
    section: Backend
    priority: medium
    estimate: 2h
    description:
      - Implement sliding window rate limiter
      - Configure 100 requests per 15 minutes
    implementationTasks:
      - task: Create RateLimitMiddleware
        done: false
      - task: Write unit tests
        done: false
    dependsOn: [MCP-AUTH-001]
    functionalRequirements: [FR-AUTH-002]
    technicalRequirements: [TR-AUTH-002]
```

Required fields: `id`, `title`, `section`, `priority`. All other fields are optional.

To create a GitHub-backed TODO and let the server assign a canonical `ISSUE-{number}` ID:

```yaml
type: request
payload:
  requestId: req-20260409T120004Z-create-issue-001
  method: workflow.todo.create
  params:
    id: ISSUE-NEW
    title: Capture sync regression in token refresh
    section: Issues
    priority: high
```

The result `item.id` will contain the assigned `ISSUE-{number}` value.

## Updating a TODO

To modify fields of an existing TODO:

```yaml
type: request
payload:
  requestId: req-20260409T120005Z-update-001
  method: workflow.todo.update
  params:
    id: MCP-AUTH-001
    remaining: Integration tests still needed
    implementationTasks:
      - task: Create TokenService
        done: true
      - task: Create JwtValidator
        done: true
      - task: Add integration tests
        done: false
```

Only include fields to change. To mark a TODO complete, set `done: true` and supply a `doneSummary`:

```yaml
type: request
payload:
  requestId: req-20260409T120006Z-update-done-001
  method: workflow.todo.update
  params:
    id: MCP-AUTH-001
    done: true
    doneSummary: JWT authentication implemented and all tests passing
```

To update the currently selected TODO without repeating the ID:

```yaml
type: request
payload:
  requestId: req-20260409T120007Z-updatesel-001
  method: workflow.todo.updateSelected
  params:
    remaining: Need to add OpenAPI annotations
```

## Deleting a TODO

To remove a TODO permanently:

```yaml
type: request
payload:
  requestId: req-20260409T120008Z-delete-001
  method: workflow.todo.delete
  params:
    id: MCP-AUTH-002
```

## Streaming Status Analysis

This streaming verb is not currently exposed by the Codex wrapper. Use
`workflow.todo.get`, `workflow.todo.query`, and `workflow.todo.analyzeRequirements`
instead.

To request an AI-driven status analysis of a TODO, showing blockers and dependency state:

```yaml
type: request
payload:
  requestId: req-20260409T120009Z-status-001
  method: workflow.todo.streamStatus
  params:
    id: MCP-AUTH-001
```

The server emits a sequence of progress events followed by a completion event:

```yaml
type: event
payload:
  event: workflow.todo.streamStatus
  data:
    eventType: status.progress
    sequence: 1
    timestamp: 2026-04-09T12:00:09Z
    message: Analyzing TODO dependencies...
    progress: 25
---
type: event
payload:
  event: workflow.todo.streamStatus
  data:
    eventType: status.complete
    sequence: 4
    timestamp: 2026-04-09T12:00:12Z
    todoId: MCP-AUTH-001
    status: ready
    blockers: []
    dependencies: [MCP-AUTH-002]
```

## Streaming Plan Generation

This streaming verb is not currently exposed by the Codex wrapper.

To generate an implementation plan for a TODO and stream the result:

```yaml
type: request
payload:
  requestId: req-20260409T120010Z-plan-001
  method: workflow.todo.streamPlan
  params:
    id: MCP-AUTH-001
```

Events follow the same `eventType: plan.progress` / `eventType: plan.complete` pattern as status streaming. The completion event includes a structured plan document.

## Streaming Implementation Execution

This streaming verb is not currently exposed by the Codex wrapper.

To execute an AI-driven implementation run for a TODO and stream progress:

```yaml
type: request
payload:
  requestId: req-20260409T120011Z-implement-001
  method: workflow.todo.streamImplement
  params:
    id: MCP-AUTH-001
```

Implementation events carry `eventType: implement.progress` and a final `eventType: implement.complete` with a results summary. Handle cancellation by sending a cancellation request; the stream emits a `eventType: status.cancelled` terminal event.

## Analyzing Requirements for a TODO

To trigger requirements analysis and surface missing FR/TR traceability:

```yaml
type: request
payload:
  requestId: req-20260409T120012Z-analyze-001
  method: workflow.todo.analyzeRequirements
  params:
    id: MCP-AUTH-001
```

The result lists any detected requirement gaps and suggests FR/TR IDs to associate with the TODO.

## Error Handling

Error envelopes include a structured `code` field:

```yaml
type: error
payload:
  requestId: req-20260409T120003Z-create-001
  code: invalid_todo_id
  message: TODO ID does not conform to canonical format
  details:
    providedId: mcp-auth-001
    expectedFormat: "^[A-Z]+-[A-Z0-9]+-\\d{3}$"
```

Common error codes:

- `todo_not_found` — no TODO with the specified ID
- `todo_already_exists` — a TODO with the same ID already exists
- `invalid_todo_id` — ID violates naming convention
- `no_selection` — `updateSelected` called with no active selection
- `stream_error` — a streaming operation failed mid-stream

## Implementation Notes

- Use `repl_invoke` from `lib/repl-invoke.sh` to build and send envelopes via `mcpserver-repl --agent-stdio`.
- The `requestId` must match `^req-\d{8}T\d{6}Z-[a-z0-9]+(?:-[a-z0-9]+)*$` for every envelope.
- All streaming operations may be cancelled by closing stdin or sending a cancellation request; the REPL guarantees a final cancellation event before closing the stream.
- After marking a TODO done, record the action in the active session log turn using `workflow.sessionlog.appendActions` with `type: edit` and the TODO ID as context.
