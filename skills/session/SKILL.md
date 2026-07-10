---
name: Session Log Management
description: Use when the user asks to "start session", "log session", "begin turn", "update turn", "complete turn", or "query session history"
version: 0.1.0
---

# Session Log Management

## Overview

To manage agent session logs, use the `workflow.sessionlog.*` REPL command namespace through the plugin wrapper (`lib/repl-invoke.ps1` / `Invoke-McpPlugin.ps1`). Session logging captures agent activity, reasoning dialog, file operations, and design decisions as a structured audit trail.

`workflow.sessionlog.*` is a plugin workflow/REPL namespace, not a literal native MCP tool namespace. Native McpServer `/mcp-transport` discovery uses names such as `sessionlog_*`, `todo_*`, and `requirements_*`; hosted-agent adapters may expose `mcp_session_*` aliases, and your agent's tool discovery may show configured MCP tools with native names such as `sessionlog_submit`, `todo_list`, and `requirements_generate`. Do not call this plugin unavailable solely because `workflow.*` names are absent from generic MCP discovery.

`workflow.*` result envelopes may include `deprecated: true`. This is success metadata that tells callers the workflow namespace is legacy-compatible and should migrate toward the canonical `client.*` surface where available; it is not a failure signal and is not a reason to use raw REST. Treat an empty `workflow.sessionlog.queryHistory` result as a valid no-match result, not as an inert wrapper. Re-check the workspace current directory, the explicit `agent` or `sourceType`, and local plugin cache/session state through the wrapper before reporting history as unavailable.

This skill covers manual operations, history queries, and the full lifecycle for agents that need direct control.

## Preferred Workflow

For most work sessions:

1. Bootstrap session logging once.
2. Open or resume the session.
3. On each user request, begin a turn.
4. Consult current session/task state before asking the user for context.
5. Update the turn with relevant files, decisions, and actions.
6. Complete the turn after verification, or record failure if blocked.

## Running the Workflow Methods

When the plugin's hooks (in `hooks/`) are active, most session management is automated and you do not need to drive it by hand. When hooks are not active for your agent, drive the lifecycle yourself through the plugin wrapper, never by hand-piping envelopes to REPL stdio:

```pwsh
pwsh -NoProfile -File "<plugin-root>/lib/repl-invoke.ps1" -Method <method> -ParamsYaml @'
<yaml params>
'@
```

The equivalent function form is `Invoke-McpPlugin.ps1 "<method>" "<yaml params>"`. For a one-shot bootstrap plus session open, prefer `<plugin-root>/lib/session-start.ps1 <workspace-path>`.

The YAML envelope blocks in this skill document the wire contract each method maps to. Pass the `params:` body to the wrapper; it wraps it in the request envelope, validates documented params, and emits single-line JSON to REPL stdio for you. If you bypass the wrapper for diagnostics and write to REPL stdio directly, send one single-line JSON request envelope per message, never formatted YAML.

Why the wrapper and not raw stdio:

- `workflow.sessionlog.beginTurn` and `openSession` are not server routes. Calling them raw returns `method_invocation_error` / `method_not_found`. The wrapper treats them as local no-ops and tracks turn state in `cache/current-turn.yaml`.
- Persisting a turn goes through `client.SessionLog.SubmitAsync`, which is strict: `actions[].order` must be an unquoted integer (`order: 1`, never `order: "1"`) or you get `JSON value could not be converted to System.Int32`. The wrapper builds the envelope with correct types.
- There is no `session.init` method. Bootstrap with `workflow.sessionlog.bootstrap` only.

## Identifier Naming Conventions

### Session IDs

Format: `<Agent>-<yyyyMMddTHHmmssZ>-<suffix>`

Regex: `^[A-Z][A-Za-z0-9]*-\d{8}T\d{6}Z-[a-z0-9]+(?:-[a-z0-9]+)*$`

- Agent name must be PascalCase (e.g. `YourAgent`)
- Timestamp must be ISO 8601 compact UTC: `yyyyMMddTHHmmssZ`
- Suffix must be lowercase kebab-case: `feature-auth`, `bugfix-timeout`

Valid examples: `YourAgent-20260409T120000Z-implement-auth`, `YourAgent-20260304T113901Z-refactor-session`

Invalid: `youragent-20260409T120000Z-task` (lowercase agent), `YourAgent-20260304-feature` (missing time component)

### Request IDs

Format: `req-<yyyyMMddTHHmmssZ>-<slugOrOrdinal>`

Regex: `^req-\d{8}T\d{6}Z-[a-z0-9]+(?:-[a-z0-9]+)*$`

Valid examples: `req-20260409T120001Z-add-jwt-001`, `req-20260409T120002Z-query-todos`

Invalid: `request-20260409T120001Z-task` (wrong prefix), `req-20260409-task` (missing time)

## Session Lifecycle

### Step 1 - Bootstrap (once per process lifetime)

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

### Step 2 - Open Session

To create a new session record at the start of a work session:

```yaml
type: request
payload:
  requestId: req-20260409T120001Z-open-001
  method: workflow.sessionlog.openSession
  params:
    agent: YourAgent
    sessionId: YourAgent-20260409T120001Z-implement-auth
    title: Implement JWT authentication
    model: <model-id>
```

```yaml
type: result
payload:
  requestId: req-20260409T120001Z-open-001
  result:
    sessionId: YourAgent-20260409T120001Z-implement-auth
    started: 2026-04-09T12:00:01Z
```

### Step 3 - Begin Turn (once per user message)

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

### Step 4 - Update Turn

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

### Step 5 - Append Dialog

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

### Step 6 - Append Actions

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

`actions[].order` must be an unquoted integer (`order: 1`, never `order: "1"`).

### Step 7 - Complete Turn

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
    errorMessage: Unable to complete - missing System.IdentityModel.Tokens.Jwt package
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
    agent: YourAgent
    limit: 10
    offset: 0
```

```yaml
type: result
payload:
  requestId: req-20260409T120008Z-history-001
  result:
    sessions:
      - agent: YourAgent
        sessionId: YourAgent-20260409T120001Z-implement-auth
        title: Implement JWT authentication
        model: <model-id>
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

1. `in_progress` - created via `beginTurn`, open for updates
2. `completed` - finalized via `completeTurn` (immutable)
3. `failed` - finalized via `failTurn` (immutable)

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

- `session_not_found`: no active session; call `openSession` first
- `session_already_exists`: session ID already in use
- `invalid_session_id`: session ID format violation
- `invalid_request_id`: request ID format violation
- `turn_not_found`: no active turn; call `beginTurn` first
- `turn_already_exists`: turn with same request ID already exists
- `turn_immutable`: cannot modify completed or failed turn

## Session Continuity After Restart

After a server restart or agent reconnect:

1. Call `workflow.sessionlog.queryHistory` to review past sessions
2. Decide whether to continue in a new session referencing the previous one in the title, or to re-open fresh
3. Re-read `AGENTS-README-FIRST.yaml` for the rotated API key before making any calls
4. Call `bootstrap` again (idempotent) then `openSession` for the new session

## Rich Field Capture and Transcript Import

Where your agent's hooks or transcript integration are available, the plugin can auto-capture rich session fields and pass them to `completeTurn`, which routes through `importRecovery` to persist them on the server. No manual steps are required when this integration is active. Captured fields include:

- `interpretation`: first agent message from the last turn
- `processingDialog`: all agent messages, tool calls, and observations
- `actions`: file edits from write and patch operations
- `filesModified`: all files changed in the turn
- `contextList`: files read as context
- `designDecisions`: agent messages containing `Decision:` or `Rationale:`
- `requirementsDiscovered`: FR/TR/TEST IDs mentioned in agent messages
- `blockers`: aborted-turn events

Secret values (API keys, Bearer tokens) are redacted before logging.

### Subagent Logging

Subagents are responsible for writing their own turns through the same session-log workflow. Parent or child models may include parent request IDs, agent names, and source metadata as tags or actions when those values are available, but plugin packages must not parse transcript files to populate session logs.

Manual recovery uses the normal `workflow.sessionlog.*` commands or non-plugin server-side transcript ingestion when explicitly invoked outside a plugin package. Plugins must not expose transcript ingestion helpers, skills, endpoint shortcuts, or parser forks.

### Non-Destructive Merge

Server-side rich fields are never overwritten by sparse incoming values. The session payload builder uses field-level merge: an empty incoming array never replaces a non-empty server-side array. This allows `completeTurn` to be called safely after rich fields have already been captured.

### Secret Redaction

The following patterns are redacted from all extracted text before logging:

- `X-Api-Key:` header values
- `apiKey:` parameter values (20+ character strings)
- `Bearer <token>` values
- `Authorization:` header values

## Implementation Notes

- Use `Invoke-McpPlugin.ps1` from `lib/repl-invoke.ps1` to build and dispatch envelopes.
- Generate request IDs with the current UTC timestamp to guarantee uniqueness: `req-$(date -u +%Y%m%dT%H%M%SZ)-<slug>`.
- Post `beginTurn` before starting any work on a user request; post `completeTurn` or `failTurn` after work ends. Never defer these calls.
- Log all design decisions in `appendDialog` with `category: decision` AND in `appendActions` with `type: design_decision`.
- Record all web sources consulted as actions with `type: web_reference` and include the URL in the description.
- At approximately every 10 interactions, verify all turns are persisted and all design decisions are captured before continuing.
