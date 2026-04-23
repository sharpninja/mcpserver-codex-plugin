---
name: Session Log Management
description: This skill should be used when the user asks to "start session", "log session", "begin turn", "update turn", "complete turn", "query session history"
---
## Initialization (Codex)

All `workflow.sessionlog.*` examples in this skill are intended for
`lib/repl-invoke.sh`, which translates them to the real `client.*` methods
that `mcpserver-repl` exposes. For a one-shot bootstrap plus session open,
prefer `bash ${CODEX_PLUGIN_ROOT}/lib/session-start.sh <workspace-path>`.

Before using any workflow commands, call `workflow.sessionlog.bootstrap` through
the wrapper to initialize the session log subsystem:

```yaml
type: request
payload:
  requestId: req-20260409T120000Z-bootstrap-001
  method: workflow.sessionlog.bootstrap
  params: {}
```

This is idempotent and should be called once per conversation context.


# Session Log Management

## Overview

To manage agent session logs, use the `workflow.sessionlog.*` namespace through
`lib/repl-invoke.sh`. Session logging captures agent activity, reasoning
dialog, file operations, and design decisions as a structured audit trail.

Most session management is automated by the plugin hooks in `hooks/`. This skill covers manual operations, history queries, and the full lifecycle for agents that need direct control.

## Identifier Naming Conventions

### Session IDs

Format: `<Agent>-<yyyyMMddTHHmmssZ>-<suffix>`

Regex: `^[A-Z][A-Za-z0-9]*-\d{8}T\d{6}Z-[a-z0-9]+(?:-[a-z0-9]+)*$`

- Agent name must be PascalCase (e.g. `ClaudeCode`, `Copilot`, `Cursor`)
- Timestamp must be ISO 8601 compact UTC: `yyyyMMddTHHmmssZ`
- Suffix must be lowercase kebab-case: `feature-auth`, `bugfix-timeout`

Valid examples: `ClaudeCode-20260409T120000Z-implement-auth`, `Copilot-20260304T113901Z-refactor-session`

Invalid: `claudecode-20260409T120000Z-task` (lowercase agent), `Copilot-20260304-feature` (missing time component)

### Request IDs

Format: `req-<yyyyMMddTHHmmssZ>-<slugOrOrdinal>`

Regex: `^req-\d{8}T\d{6}Z-[a-z0-9]+(?:-[a-z0-9]+)*$`

Valid examples: `req-20260409T120001Z-add-jwt-001`, `req-20260409T120002Z-query-todos`

Invalid: `request-20260409T120001Z-task` (wrong prefix), `req-20260409-task` (missing time)

## Session Lifecycle

### Step 1 — Bootstrap (once per process lifetime)

Bootstrap initializes the session log subsystem. This operation is idempotent:

```yaml
type: request
payload:
  requestId: req-20260409T120000Z-bootstrap-001
  method: workflow.sessionlog.bootstrap
  params: {}
```

```yaml
type: result
payload:
  requestId: req-20260409T120000Z-bootstrap-001
  result:
    initialized: true
```

### Step 2 — Open Session

To create a new session record at the start of a work session:

```yaml
type: request
payload:
  requestId: req-20260409T120001Z-open-001
  method: workflow.sessionlog.openSession
  params:
    agent: ClaudeCode
    sessionId: ClaudeCode-20260409T120001Z-implement-auth
    title: Implement JWT authentication
    model: claude-sonnet-4-6
```

```yaml
type: result
payload:
  requestId: req-20260409T120001Z-open-001
  result:
    sessionId: ClaudeCode-20260409T120001Z-implement-auth
    started: 2026-04-09T12:00:01Z
```

### Step 3 — Begin Turn (once per user message)

To start a new turn before working on a user request:

```yaml
type: request
payload:
  requestId: req-20260409T120002Z-begin-001
  method: workflow.sessionlog.beginTurn
  params:
    requestId: req-20260409T120002Z-add-jwt-001
    queryTitle: Add JWT authentication
    queryText: Implement JWT token generation and validation for the API
```

```yaml
type: result
payload:
  requestId: req-20260409T120002Z-begin-001
  result:
    turnRequestId: req-20260409T120002Z-add-jwt-001
    status: in_progress
    timestamp: 2026-04-09T12:00:02Z
```

### Step 4 — Update Turn

To record interpretation, response summary, tags, and referenced files during work:

```yaml
type: request
payload:
  requestId: req-20260409T120003Z-update-001
  method: workflow.sessionlog.updateTurn
  params:
    response: Created TokenService and JwtValidator classes
    interpretation: User wants JWT authentication with token generation and validation
    tokenCount: 1250
    tags:
      - feature
      - security
      - FR-AUTH-001
    contextList:
      - src/Services/TokenService.cs
      - src/Services/JwtValidator.cs
```

### Step 5 — Append Dialog

To record reasoning steps, tool calls, observations, and decisions as the work progresses:

```yaml
type: request
payload:
  requestId: req-20260409T120004Z-dialog-001
  method: workflow.sessionlog.appendDialog
  params:
    dialogItems:
      - timestamp: 2026-04-09T12:00:04Z
        role: model
        content: Analyzing authentication requirements and existing patterns...
        category: reasoning
      - timestamp: 2026-04-09T12:00:05Z
        role: model
        content: |
          Decision: Use HS256 for JWT signing.
          Rationale: Symmetric key simplifies key management for this internal service.
          Alternatives: RS256 adds key distribution complexity without benefit here.
        category: decision
```

Valid `category` values: `reasoning`, `tool_call`, `tool_result`, `observation`, `decision`.

Valid `role` values: `model`, `tool`, `system`, `user`.

### Step 6 — Append Actions

To record file operations and other work artifacts:

```yaml
type: request
payload:
  requestId: req-20260409T120005Z-actions-001
  method: workflow.sessionlog.appendActions
  params:
    actions:
      - order: 1
        description: Created TokenService with JWT generation
        type: create
        status: completed
        filePath: src/Services/TokenService.cs
      - order: 2
        description: Created JwtValidator for token validation
        type: create
        status: completed
        filePath: src/Services/JwtValidator.cs
      - order: 3
        description: Chose HS256 for JWT signing (internal service, symmetric key)
        type: design_decision
        status: completed
        filePath: ""
```

Standard action `type` values: `edit`, `create`, `delete`, `design_decision`, `commit`, `pr_comment`, `issue_comment`, `web_reference`, `dependency_add`.

### Step 7 — Complete Turn

To finalize a turn as successfully completed (immutable after this call):

```yaml
type: request
payload:
  requestId: req-20260409T120006Z-complete-001
  method: workflow.sessionlog.completeTurn
  params:
    response: |
      JWT authentication implemented:
      - TokenService generates HS256-signed tokens
      - JwtValidator validates and extracts claims
      - Services registered in Startup.cs
      - All unit tests passing
```

### Failing a Turn

To mark a turn as failed with an error description:

```yaml
type: request
payload:
  requestId: req-20260409T120007Z-fail-001
  method: workflow.sessionlog.failTurn
  params:
    errorMessage: Unable to complete — missing System.IdentityModel.Tokens.Jwt package
    errorCode: dependency_missing
```

Both `completeTurn` and `failTurn` produce an immutable terminal state. No further `updateTurn`, `appendDialog`, or `appendActions` calls are allowed on a completed or failed turn.

## Querying Session History

To browse previous sessions for context continuity:

```yaml
type: request
payload:
  requestId: req-20260409T120008Z-history-001
  method: workflow.sessionlog.queryHistory
  params:
    agent: ClaudeCode
    limit: 10
    offset: 0
```

```yaml
type: result
payload:
  requestId: req-20260409T120008Z-history-001
  result:
    sessions:
      - agent: ClaudeCode
        sessionId: ClaudeCode-20260409T120001Z-implement-auth
        title: Implement JWT authentication
        model: claude-sonnet-4-6
        started: 2026-04-09T12:00:01Z
        lastUpdated: 2026-04-09T12:30:00Z
        status: completed
        turnCount: 3
        filesModifiedCount: 5
        tags: [auth, jwt, security]
    totalCount: 1
    offset: 0
    limit: 10
```

Omit `agent` to query across all agents. Use `offset` and `limit` for pagination.

## Turn Lifecycle State Machine

A turn transitions through these states only in forward order:

1. `in_progress` — created via `beginTurn`, open for updates
2. `completed` — finalized via `completeTurn` (immutable)
3. `failed` — finalized via `failTurn` (immutable)

Any attempt to call `updateTurn`, `appendDialog`, or `appendActions` on a `completed` or `failed` turn returns a `turn_immutable` error.

## Error Handling

```yaml
type: error
payload:
  requestId: req-20260409T120003Z-update-001
  code: turn_immutable
  message: Turn is immutable (status: completed)
  details:
    turnRequestId: req-20260409T120002Z-add-jwt-001
    currentStatus: completed
    hint: Begin a new turn instead
```

Common error codes:

- `session_not_found` — no active session; call `openSession` first
- `session_already_exists` — session ID already in use
- `invalid_session_id` — session ID format violation
- `invalid_request_id` — request ID format violation
- `turn_not_found` — no active turn; call `beginTurn` first
- `turn_already_exists` — turn with same request ID already exists
- `turn_immutable` — cannot modify completed or failed turn

## Session Continuity After Restart

After a server restart or agent reconnect:

1. Call `workflow.sessionlog.queryHistory` to review past sessions
2. Decide whether to continue in a new session referencing the previous one in the title, or to re-open fresh
3. Re-read `AGENTS-README-FIRST.yaml` for the rotated API key before making any calls
4. Call `bootstrap` again (idempotent) then `openSession` for the new session

## Implementation Notes

- Use `repl_invoke` from `lib/repl-invoke.sh` to build and dispatch envelopes.
- Generate request IDs with the current UTC timestamp to guarantee uniqueness: `req-$(date -u +%Y%m%dT%H%M%SZ)-<slug>`.
- Post `beginTurn` before starting any work on a user request; post `completeTurn` or `failTurn` after work ends. Never defer these calls.
- Log all design decisions in `appendDialog` with `category: decision` AND in `appendActions` with `type: design_decision`.
- Record all web sources consulted as actions with `type: web_reference` and include the URL in the description.
- At approximately every 10 interactions, verify all turns are persisted and all design decisions are captured before continuing.
