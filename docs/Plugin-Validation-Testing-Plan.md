# McpServer Agent Plugin Validation Testing Plan

This plan defines a thorough validation strategy for `mcpserver-codex-plugin` and a reusable parity checklist for the other three agent plugins:

- `mcpserver-claude-code-plugin`
- `mcpserver-copilot-plugin`
- `mcpserver-cline-plugin`

The Codex plugin is the reference implementation for this plan because it has a compact shell-based lifecycle, concrete Bats coverage, and recently exposed the same class of failure that can affect every plugin: a workflow shim routed through an unauthenticated REPL path instead of the workspace-aware marker/auth path.

## Goals

1. Prove every plugin can discover and verify `AGENTS-README-FIRST.yaml` before MCP usage.
2. Prove every plugin preserves the required agent identity in session state, logs, TODOs, and requirements calls.
3. Prove every plugin routes workflow commands through the correct transport, marker, workspace, API key, and fallback path.
4. Prove every plugin can create, update, query, and complete session-log turns without silent local-only success.
5. Prove TODO, requirements, and GraphRAG operations work through the supported plugin path.
6. Prove stop/build enforcement gates block and pass in the correct scenarios.
7. Prove offline cache behavior is deterministic, durable, replayable, and not lossy.
8. Prove cross-plugin behavior is equivalent even when the implementation runtimes differ.
9. Produce evidence that can be inspected later: commands, exit codes, session IDs, request IDs, cache files, logs, and server readback.

## Non-Goals

1. This plan does not test the entire McpServer backend. Backend tests belong in `F:\GitHub\McpServer`.
2. This plan does not require all four plugins to share identical file layouts.
3. This plan does not require live production credentials. Live tests should use a disposable workspace or a known test workspace marker.
4. This plan does not replace manual validation inside each host product UI. It defines the command-level and contract-level evidence that must exist before UI validation is trusted.

## Reference Contract

Each plugin must satisfy the workspace marker contract exposed in `AGENTS-README-FIRST.yaml`.

The shared contract includes:

1. Read the marker from the workspace root or nearest parent.
2. Verify marker HMAC signature before calling MCP endpoints.
3. Call `/health` with a random nonce and confirm the same nonce is echoed.
4. Stop MCP usage after signature, health, nonce, or auth failure.
5. Use the agent-specific plugin path, not a different agent plugin or raw REST fallback.
6. Open a session log with the real agent identity.
7. Open a turn for each user message before doing work.
8. Persist updates after meaningful progress.
9. Complete or fail the turn before final output.
10. Record actions, decisions, files, blockers, validation evidence, and requirements discoveries.
11. Use the supported workflow namespaces for session, TODO, requirements, and GraphRAG.
12. Avoid direct edits to TODO backing files when trusted MCP TODO operations are available.

## Plugin Inventory

### Codex

Repository: `F:\GitHub\mcpserver-codex-plugin`

Primary files:

- `.codex-plugin/plugin.json`
- `lib/session-start.sh`
- `lib/user-prompt-submit.sh`
- `lib/repl-invoke.sh`
- `lib/marker-resolver.sh`
- `lib/cache-manager.sh`
- `lib/code-verify.sh`
- `lib/stop-gate.sh`
- `skills/session/SKILL.md`
- `skills/todo/SKILL.md`
- `skills/requirements/SKILL.md`
- `skills/graphrag/SKILL.md`
- `skills/device/SKILL.md`
- `skills/enforcement/SKILL.md`
- `tests/*.bats`

Expected identity:

- Plugin root variable: `CODEX_PLUGIN_ROOT`
- Agent env: `PLUGIN_AGENT_NAME=Codex`
- Session prefix: `Codex-`
- Source type: `Codex`

### Claude Code

Repository: `F:\GitHub\mcpserver-claude-code-plugin`

Primary files:

- `.claude-plugin`
- `.mcp.json`
- `hooks/hooks.json`
- `hooks/scripts/session-start.sh`
- `hooks/scripts/user-prompt-submit.sh`
- `hooks/scripts/stop-gate.sh`
- `hooks/scripts/pre-compact.sh`
- `hooks/scripts/post-compact.sh`
- `hooks/scripts/plan-approved.sh`
- `hooks/scripts/plan-modified.sh`
- `hooks/scripts/code-verify.sh`
- `lib/repl-invoke.sh`
- `lib/repl-invoke.ps1`
- `lib/marker-resolver.sh`
- `lib/marker-resolver.ps1`
- `tests/*.bats`
- `tests/*.ps1.tests.ps1`

Expected identity:

- Plugin root variable: `CLAUDE_PLUGIN_ROOT`
- Agent env: `PLUGIN_AGENT_NAME=Claude`
- Session prefix: `Claude-`
- Source type: `Claude`

### Copilot

Repository: `F:\GitHub\mcpserver-copilot-plugin`

Primary files:

- `plugin.json`
- `hooks.json`
- `.mcp.json`
- `hooks/scripts/session-start.sh`
- `hooks/scripts/user-prompt-submit.sh`
- `hooks/scripts/stop-gate.sh`
- `hooks/scripts/pre-compact.sh`
- `hooks/scripts/post-compact.sh`
- `hooks/scripts/plan-approved.sh`
- `hooks/scripts/plan-modified.sh`
- `hooks/scripts/code-verify.sh`
- `lib/repl-invoke.sh`
- `lib/marker-resolver.sh`
- `tests/*.bats`

Expected identity:

- Plugin root variable: `PLUGIN_ROOT`
- Agent env: `PLUGIN_AGENT_NAME=Copilot`
- Session prefix: `Copilot-`
- Source type: `Copilot`

### Cline

Repository: `F:\GitHub\mcpserver-cline-plugin`

Primary files:

- `package.json`
- `server.json`
- `src/index.ts`
- `src/transport/repl-bridge.ts`
- `src/discovery/marker-resolver.ts`
- `src/tools/session.ts`
- `src/tools/session-shim.ts`
- `src/tools/todo.ts`
- `src/tools/requirements.ts`
- `src/tools/graphrag.ts`
- `src/cache/cache-manager.ts`
- `lib/user-prompt-submit.sh`
- `lib/stop-gate.sh`
- `lib/code-verify.sh`
- `tests/*.test.ts`

Expected identity:

- MCP server env: `MCP_WORKSPACE_PATH`
- Cache env: `MCPSERVER_CACHE_DIR`
- Agent env: `PLUGIN_AGENT_NAME=Cline`
- Session prefix: `Cline-`
- Source type: `Cline`

## Test Levels

Every plugin should pass the following levels before being treated as validated.

### Level 0 - Repository Hygiene

Purpose: prove the local repo is in a known state before testing.

Checks:

1. Capture branch and status.
2. Capture plugin version file and manifest version.
3. Capture current test command availability.
4. Identify pre-existing dirty files and separate them from test-generated artifacts.
5. Confirm cache directories are ignored or test-scoped.

Evidence:

- `git status --short --branch`
- `git diff --name-only`
- manifest version output
- test command version output

Pass criteria:

- Dirty tree is understood and not mixed with test output.
- Required tools are present or the missing tool is recorded as a blocker.

### Level 1 - Static Manifest and Packaging Validation

Purpose: prove host-facing metadata is valid and agent-specific.

Codex checks:

1. `.codex-plugin/plugin.json` is valid JSON.
2. `name`, `version`, `description`, `skillsPath`, and repository fields exist.
3. `skillsPath` points to a real directory.
4. All referenced skills contain `SKILL.md`.

Claude Code checks:

1. `hooks/hooks.json` is valid JSON.
2. `.mcp.json` is valid JSON.
3. Hook commands point to real scripts.
4. Shell and PowerShell helper pairs exist where expected.
5. Skill references point to real files.

Copilot checks:

1. `plugin.json` is valid JSON.
2. `hooks.json` is valid JSON.
3. `skills` entries point to real `SKILL.md` files.
4. `mcpServers.mcpserver.env.PLUGIN_AGENT_NAME` is `Copilot`.
5. Hook commands point to real scripts.

Cline checks:

1. `package.json` is valid JSON.
2. `server.json` is valid JSON.
3. `package.json` `main` and `bin` point to build output.
4. `server.json` command and args are consistent with `package.json`.
5. TypeScript source files referenced by tools exist.

Pass criteria:

- JSON parses.
- Every referenced script, skill, command, or output path exists.
- Agent identity is not copied from another plugin.

### Level 2 - Syntax and Build Validation

Purpose: catch script and compile failures before runtime tests.

Codex commands:

```bash
bash -n lib/*.sh
bats --tap tests/session-start.bats
bats --tap tests/user-prompt-submit.bats
bats --tap tests/stop-gate.bats
bats --tap tests/code-verify.bats
bats --tap tests/repl-invoke-shim.bats
```

Claude Code commands:

```bash
bash -n hooks/scripts/*.sh lib/*.sh
bats --tap tests/
pwsh -NoLogo -NoProfile -File tests/repl-invoke-shim.ps1.tests.ps1
```

Copilot commands:

```bash
bash -n hooks/scripts/*.sh lib/*.sh
bats --tap tests/
```

Cline commands:

```bash
npm ci
npm run build
npm test
```

Pass criteria:

- All scripts parse.
- Unit tests pass.
- TypeScript compiles for Cline.
- No test depends on user-global cache state.

### Level 3 - Marker Discovery and Trust Validation

Purpose: prove MCP calls never run from an untrusted marker.

Test cases:

1. Marker in workspace root is found.
2. Marker in parent directory is found when command starts in a child folder.
3. Missing marker returns untrusted or no-session without probing MCP endpoints.
4. Invalid HMAC returns untrusted and blocks MCP endpoint usage.
5. Rotated API key in marker is used on the next bootstrap.
6. Health endpoint failure returns untrusted and stops.
7. Health nonce mismatch returns untrusted and stops.
8. Marker with CRLF parses the same as LF.
9. Marker with `prompt: |` parses if helper code inspects prompt payloads.
10. Marker with `prompt: |-` parses if helper code inspects prompt payloads.
11. Nested endpoint fields are parsed correctly.
12. Agent plugin contract digest or policy fields are included in signature verification when present.

Fixtures:

- `trusted-marker.yaml`
- `trusted-marker-crlf.yaml`
- `bad-signature-marker.yaml`
- `bad-nonce-marker.yaml`
- `missing-api-key-marker.yaml`
- `rotated-api-key-marker.yaml`

Pass criteria:

- Trusted marker returns verified.
- Untrusted marker never reaches session, TODO, requirements, or GraphRAG calls.
- Failure output includes `MCP_UNTRUSTED` or plugin-native equivalent.
- No plugin proceeds on marker mismatch.

### Level 4 - REPL Transport and Workflow Shim Validation

Purpose: prove each workflow command reaches the correct client method through the authenticated, workspace-aware path.

Shared commands:

- `workflow.sessionlog.openSession`
- `workflow.sessionlog.beginTurn`
- `workflow.sessionlog.updateTurn`
- `workflow.sessionlog.appendDialog`
- `workflow.sessionlog.appendActions`
- `workflow.sessionlog.completeTurn`
- `workflow.sessionlog.failTurn`
- `workflow.sessionlog.queryHistory`
- `workflow.todo.query`
- `workflow.todo.get`
- `workflow.todo.create`
- `workflow.todo.update`
- `workflow.todo.delete`
- `workflow.todo.analyzeRequirements`
- `workflow.requirements.listFr`
- `workflow.requirements.createFr`
- `workflow.requirements.updateFr`
- `workflow.requirements.generateDocument`
- `workflow.requirements.ingestDocument`
- GraphRAG workflow/tool commands supported by the plugin

Required negative tests:

1. Stub REPL returns `method_not_found` for `workflow.*`; plugin shim must not expose that to the caller when a supported typed fallback exists.
2. Stub REPL returns `Authentication required` on a direct workspace path; plugin must retry or route through a compatibility marker path when that is the supported fallback.
3. Stub REPL exits non-zero; plugin must cache writes where caching is expected.
4. Stub REPL returns `type: error`; plugin command must exit non-zero unless the operation is explicitly allowed to degrade.
5. `mcpserver-repl` missing from `PATH`; plugin must attempt installation or return a clear failure according to its design.

Pass criteria:

- No supported `workflow.*` command falls through as `method_not_found`.
- Session and requirements queries use authenticated marker context.
- YAML-over-STDIO envelopes include a unique request ID.
- Parameter names match live client method names.
- Empty result bodies are investigated, not treated as proof of data persistence.

### Level 5 - Session Lifecycle Validation

Purpose: prove each plugin opens and maintains real session logs.

Test sequence:

1. Start from an empty plugin cache.
2. Run session-start hook or MCP server start path.
3. Verify `session-state.yaml` or equivalent cache contains:
   - `status: verified`
   - correct `sourceType`
   - correct `sessionId` prefix
   - title
   - model
   - workspace path
   - base URL
4. Query server session logs by agent and session ID.
5. Verify the session exists on the server, not only in cache.
6. Run user-prompt hook with a synthetic prompt.
7. Verify `current-turn.yaml` or equivalent contains:
   - request ID
   - query title
   - opened timestamp
   - `status: in_progress`
   - original prompt text
8. Append a dialog item.
9. Append an action with a file path.
10. Complete the turn.
11. Query server readback.
12. Verify turn status is completed, action is present, and file path is included.

Pass criteria:

- Session IDs match `<Agent>-<yyyyMMddTHHmmssZ>-<slug>`.
- Request IDs match `req-<yyyyMMddTHHmmssZ>-<slug>`.
- Source type and session prefix are the same agent.
- No plugin logs as `Assistant`, lowercase agent names, or another plugin identity.
- Server readback confirms the completed turn.

### Level 6 - Per-User-Message Hook Validation

Purpose: prove a user prompt cannot bypass session turn creation.

Test cases:

1. Valid prompt opens a turn.
2. Empty prompt opens a turn with fallback title.
3. Multi-line prompt preserves line breaks.
4. Prompt containing quotes, colons, brackets, YAML-looking text, and JSON-looking text is safely embedded.
5. Prompt containing non-ASCII characters is preserved or safely encoded.
6. No active session triggers bootstrap or graceful no-session status as designed.
7. Corrupt cache does not crash the host hook.
8. Hook emits host-compatible JSON.
9. Hook does not write duplicate turn IDs under rapid repeated prompts.
10. Hook output includes any required additional context/reminders.

Pass criteria:

- The host receives valid JSON.
- The cache contains exactly one current turn for the last prompt.
- The server receives the opened turn when online.
- Offline failure is cached or explicitly reported according to plugin design.

### Level 7 - Stop and Build Gate Validation

Purpose: prove final responses are blocked when session or build state is unsafe.

Test cases:

1. No turn file returns no-turn or equivalent non-blocking status.
2. Completed turn with clean build passes.
3. In-progress turn self-heals if the completion shim is available.
4. In-progress turn blocks if self-heal cannot run.
5. Completed turn with failed build and code edits blocks.
6. Completed turn with failed build and explicit accept-failure marker passes once.
7. Accept-failure marker is consumed.
8. Code edits increment only through action append logic, not twice through verification.
9. Build verification writes `lastBuildStatus`.
10. Stop hook output is valid JSON for the host.

Pass criteria:

- Unsafe combinations block.
- Accepted failure is explicit and one-use.
- No hook loops indefinitely.
- Hook output contains the active request ID when blocking.

### Level 8 - Code Verification Hook Validation

Purpose: prove source edits trigger the correct validation and session-log action.

Test cases:

1. No changed source files produces a no-op or skipped status.
2. Changed source file triggers the configured validation command.
3. Successful validation records an action with `type: test` or `type: build`.
4. Failed validation records failure status and blocks Stop when code edits are present.
5. Generated or cache files do not count as source edits.
6. Repeated verification does not double-count the same edit unless there is a new append action.
7. Validation command timeout is recorded as failure.
8. Shell quoting works for workspace paths containing spaces.
9. Validation works from nested directories.
10. Validation does not mutate unrelated files.

Pass criteria:

- The hook catches real failures.
- The hook does not create false code edit counts.
- The session log includes validation evidence.

### Level 9 - TODO Workflow Validation

Purpose: prove backlog operations use MCP TODO APIs instead of direct file edits.

Test cases:

1. Query open TODOs.
2. Query by ID.
3. Query by priority.
4. Query by keyword.
5. Create a TODO with a canonical ID.
6. Reject invalid lowercase IDs when the server enforces canonical IDs.
7. Create GitHub-backed TODO with `ISSUE-NEW` when configured.
8. Update priority/status/notes.
9. Complete a TODO.
10. Delete or remove a test TODO.
11. Select a TODO and update selected.
12. Server-side TODO schema failure is reported, not hidden by direct file editing.

Pass criteria:

- TODO changes appear in server readback.
- Plugin does not edit `docs/todo.yaml` or other backing files directly.
- Error cases preserve the server error text.

### Level 10 - Requirements Workflow Validation

Purpose: prove requirements import/export works and is binary-safe.

Test cases:

1. List FR, TR, TEST, and mappings.
2. Create, update, and delete a test FR.
3. Create, update, and delete a test TR.
4. Create, update, and delete a test TEST requirement.
5. Upsert and delete a mapping.
6. Generate functional requirements document.
7. Generate technical requirements document.
8. Generate testing requirements document.
9. Generate traceability matrix.
10. Generate all-documents bundle.
11. Generate wiki ZIP bundle and return it as base64 when needed.
12. Ingest markdown content.
13. Ingest wiki document map with timestamps.
14. Resolve timestamp conflicts with explicit preferred platform.
15. Fail timestamp conflicts without explicit preference.
16. Preserve server-generated docs instead of hand-authoring exports.

Pass criteria:

- Text exports are readable and complete.
- ZIP exports are binary-safe.
- Ingest operations report created, updated, deleted, and ignored counts.
- Requirement IDs remain canonical.

### Level 11 - GraphRAG Workflow Validation

Purpose: prove knowledge graph operations use the plugin transport and fail safely.

Test cases:

1. Search context with a simple query.
2. Search with filters.
3. Pack context from selected source IDs.
4. List sources.
5. Ingest an ad hoc text document when supported.
6. Query with insufficient graph data and verify a clear empty result.
7. Query while MCP server is down and verify cache/failure behavior.
8. Query with large text and verify payload is chunked or rejected clearly.

Pass criteria:

- Results come from MCP, not local invented context.
- Source IDs and documents are returned with enough evidence to cite later.
- Empty results are distinguishable from transport failures.

### Level 12 - Offline Cache Validation

Purpose: prove writes survive MCP outage and replay correctly.

Test cases:

1. Server unavailable during session start.
2. Server unavailable during beginTurn.
3. Server unavailable during appendDialog.
4. Server unavailable during appendActions.
5. Server unavailable during completeTurn.
6. Server unavailable during TODO create/update.
7. Server unavailable during requirements create/update.
8. Pending cache file includes method, params, timestamp, and retry count.
9. Flush replays in order.
10. Flush deletes successful items.
11. Flush increments retry count for failed items.
12. Flush stops retrying after max retry count.
13. Cache survives process restart.
14. Cache path override works.
15. Cache does not leak API keys into pending files unless explicitly required and protected.

Pass criteria:

- No acknowledged write is lost.
- Replay order is deterministic.
- Failed replay remains inspectable.
- Sensitive marker data is not written unnecessarily.

### Level 13 - Compatibility Marker Validation

Purpose: prove plugins can bridge client auth expectations when the live REPL needs a marker file in the process workspace.

Test cases:

1. Direct workspace path succeeds with a normal marker.
2. Direct workspace path fails with `Authentication required`.
3. Compatibility marker path succeeds.
4. Compatibility marker includes current API key.
5. Compatibility marker includes current base URL.
6. Compatibility marker includes current workspace path.
7. Compatibility marker signature matches its payload.
8. Temporary compatibility marker directory is deleted after use.
9. Compatibility marker is not created if trusted marker state is missing.
10. Compatibility marker path is used for queryHistory and submit paths that require marker auth.

Pass criteria:

- The auth-warning class of bug is covered by a regression test.
- Query and submit calls can be verified by server readback.
- Temporary marker cleanup is reliable.

### Level 14 - Cross-Plugin Parity Validation

Purpose: prove all plugins satisfy the same behavior contract.

For each plugin, execute the same scenario:

1. Create an isolated test workspace with a trusted marker.
2. Start plugin session.
3. Open user turn.
4. Query TODOs.
5. Create and complete a disposable TODO.
6. Create a disposable FR/TR/TEST requirement set.
7. Export requirements docs.
8. Run a GraphRAG search.
9. Append a session action.
10. Complete turn.
11. Run stop gate.
12. Query server readback.

Expected agent-specific differences:

- Codex uses `CODEX_PLUGIN_ROOT` and scripts under `lib/`.
- Claude Code uses `CLAUDE_PLUGIN_ROOT`, `hooks/scripts/`, and may have both shell and PowerShell helpers.
- Copilot uses `PLUGIN_ROOT`, `hooks.json`, and `hooks/scripts/`.
- Cline uses a Node MCP server and TypeScript tools.

Expected shared results:

- Same workspace path.
- Same MCP server base URL.
- Same canonical API endpoints.
- Same workflow command semantics.
- Same server-side object shapes.
- Different but correct agent identities.

Pass criteria:

- Each plugin creates exactly one session for its agent.
- Each plugin creates exactly one completed turn for the scenario.
- Disposable TODO and requirements artifacts are cleaned up or explicitly marked as test artifacts.
- No plugin writes another plugin's identity.
- No plugin depends on another plugin's root env var.

### Level 15 - Live Integration Validation

Purpose: prove behavior against a real running McpServer instance.

Preconditions:

1. McpServer is running.
2. Test workspace is registered.
3. Test workspace has a fresh marker.
4. API key in marker is current.
5. `mcpserver-repl` is available.
6. Host shell path is known: Git Bash on Windows is preferred for these plugin scripts.

Live test sequence:

1. Record server `/health` with nonce.
2. Run plugin session start.
3. Capture session ID.
4. Query server for session ID through REST readback or trusted plugin query path.
5. Run user prompt hook.
6. Capture request ID.
7. Append actions and dialog.
8. Complete turn.
9. Query server readback for session and turn.
10. Run stop gate.
11. Confirm status passed.

Required evidence:

- Server base URL.
- Health nonce and echoed nonce.
- Plugin name and version.
- Agent source type.
- Session ID.
- Request ID.
- Server readback count.
- Stop gate output.

Pass criteria:

- No `Authentication required` warning.
- No `method_not_found` for supported workflow commands.
- Server readback contains the new session and completed turn.
- Stop gate passes.

### Level 16 - Host-Specific Manual Validation

Purpose: prove host integration, not just command scripts.

Codex manual checks:

1. Install or enable the local Codex plugin.
2. Start a Codex thread in a marker-backed workspace.
3. Confirm session starts automatically.
4. Submit a prompt.
5. Confirm a turn opens.
6. Make a small edit.
7. Confirm code verification runs.
8. Finalize response.
9. Confirm stop gate passes.

Claude Code manual checks:

1. Install plugin through Claude Code.
2. Confirm SessionStart hook runs.
3. Approve a plan and confirm TODO creation.
4. Edit a plan and confirm TODO sync.
5. Trigger compaction and confirm pre/post compaction session updates.
6. Finalize with stop gate pass.

Copilot manual checks:

1. Install plugin through Copilot plugin system.
2. Confirm `hooks.json` hooks are loaded.
3. Confirm MCP server entry runs `mcpserver-repl --agent-stdio`.
4. Submit prompt and verify turn.
5. Trigger write/edit hook and verify code verification.
6. Finalize with stop gate pass.

Cline manual checks:

1. Build TypeScript output.
2. Configure Cline with `server.json`.
3. Start MCP server.
4. List available tools.
5. Invoke session, TODO, requirements, and GraphRAG tools.
6. Confirm cache and enforcement helper scripts work with the Node server.

Pass criteria:

- Host recognizes plugin.
- Host runs hooks or tools at the expected lifecycle points.
- Server readback matches command-level tests.

## Regression Test Catalog

The following regression IDs should be implemented as automated tests where practical.

### Marker and Trust

- `MARKER-001`: trusted marker verifies.
- `MARKER-002`: missing marker blocks MCP usage.
- `MARKER-003`: bad HMAC blocks MCP usage.
- `MARKER-004`: health failure blocks MCP usage.
- `MARKER-005`: nonce mismatch blocks MCP usage.
- `MARKER-006`: CRLF marker parses.
- `MARKER-007`: rotated API key is reloaded.
- `MARKER-008`: nested endpoint fields parse.
- `MARKER-009`: plugin contract digest is covered.

### REPL and Workflow Routing

- `REPL-001`: `workflow.sessionlog.openSession` maps to session submit/open behavior.
- `REPL-002`: `workflow.sessionlog.beginTurn` persists current turn.
- `REPL-003`: `workflow.sessionlog.completeTurn` flips status to completed.
- `REPL-004`: `workflow.sessionlog.queryHistory` uses authenticated workspace marker path.
- `REPL-005`: supported `workflow.todo.*` commands do not fall through to `method_not_found`.
- `REPL-006`: supported `workflow.requirements.*` commands do not fall through to `method_not_found`.
- `REPL-007`: live client parameter names match plugin wrapper parameter names.
- `REPL-008`: `type: error` causes non-zero exit unless degradation is intentional.
- `REPL-009`: compatibility marker retries or routing work for auth-sensitive methods.

### Session

- `SESSION-001`: session ID uses correct agent prefix.
- `SESSION-002`: source type uses PascalCase real agent identity.
- `SESSION-003`: title and model are recorded.
- `SESSION-004`: workspace path is recorded.
- `SESSION-005`: server readback includes session.
- `SESSION-006`: begin turn creates request ID.
- `SESSION-007`: append actions records file paths.
- `SESSION-008`: append dialog records categories.
- `SESSION-009`: complete turn is persisted to server.
- `SESSION-010`: fail turn is persisted to server.

### Hooks and Enforcement

- `HOOK-001`: user prompt hook emits valid JSON.
- `HOOK-002`: prompt text is preserved.
- `HOOK-003`: empty prompt gets fallback title.
- `HOOK-004`: stop gate passes completed clean turn.
- `HOOK-005`: stop gate blocks in-progress turn when self-heal is unavailable.
- `HOOK-006`: stop gate blocks failed build with edits.
- `HOOK-007`: accept-failure marker is one-use.
- `HOOK-008`: code verification records build/test result.
- `HOOK-009`: compaction hooks persist state before and after compaction where supported.
- `HOOK-010`: plan hooks create and update TODOs where supported.

### TODO

- `TODO-001`: query open TODOs.
- `TODO-002`: create canonical TODO.
- `TODO-003`: reject invalid TODO ID.
- `TODO-004`: update selected TODO.
- `TODO-005`: complete TODO.
- `TODO-006`: delete test TODO.
- `TODO-007`: server schema failure is surfaced.

### Requirements

- `REQ-001`: list FRs.
- `REQ-002`: create/update/delete FR.
- `REQ-003`: create/update/delete TR.
- `REQ-004`: create/update/delete TEST.
- `REQ-005`: upsert/delete mapping.
- `REQ-006`: generate markdown docs.
- `REQ-007`: generate wiki ZIP docs binary-safely.
- `REQ-008`: ingest markdown.
- `REQ-009`: ingest wiki document map.
- `REQ-010`: timestamp conflict requires preference.

### GraphRAG

- `GRAPH-001`: query context search.
- `GRAPH-002`: pack context.
- `GRAPH-003`: list sources.
- `GRAPH-004`: no-results response is distinct from failure.
- `GRAPH-005`: server-down failure is cached or clear.

### Cache

- `CACHE-001`: pending write created when server unavailable.
- `CACHE-002`: pending write includes method and params.
- `CACHE-003`: flush succeeds and removes item.
- `CACHE-004`: flush failure increments retry.
- `CACHE-005`: max retry is enforced.
- `CACHE-006`: cache path override works.
- `CACHE-007`: cache survives process restart.

### Cross-Plugin

- `PARITY-001`: all plugins pass marker trust scenario.
- `PARITY-002`: all plugins create real server session.
- `PARITY-003`: all plugins complete one turn.
- `PARITY-004`: all plugins query TODOs.
- `PARITY-005`: all plugins export requirements.
- `PARITY-006`: all plugins run GraphRAG search.
- `PARITY-007`: all plugins preserve their own identity.
- `PARITY-008`: no plugin depends on another plugin's root variable.
- `PARITY-009`: all plugins block untrusted marker.
- `PARITY-010`: all plugins handle offline server deterministically.

## Recommended Automation Layout

Use the Codex plugin as the template for shared shell tests.

Suggested shared folders:

- `tests/fixtures/markers/`
- `tests/fixtures/repl/`
- `tests/fixtures/workspaces/`
- `tests/helpers/assertions.bash`
- `tests/helpers/fake-mcpserver-repl`
- `tests/helpers/fake-curl`
- `tests/helpers/fake-openssl`
- `tests/helpers/session-log-readback.ps1`
- `tests/helpers/plugin-matrix.ps1`

Suggested Codex test files:

- `tests/manifest.bats`
- `tests/marker-resolver.bats`
- `tests/session-start.bats`
- `tests/user-prompt-submit.bats`
- `tests/stop-gate.bats`
- `tests/code-verify.bats`
- `tests/repl-invoke-shim.bats`
- `tests/cache-manager.bats`
- `tests/live-session-smoke.bats`

Suggested Claude Code test files:

- `tests/manifest.bats`
- `tests/hooks.bats`
- `tests/marker-resolver.bats`
- `tests/repl-invoke-shim.bats`
- `tests/repl-invoke-shim.ps1.tests.ps1`
- `tests/cache-manager.bats`
- `tests/stop-gate.bats`
- `tests/skills.bats`
- `tests/live-session-smoke.bats`

Suggested Copilot test files:

- `tests/manifest.bats`
- `tests/hooks.bats`
- `tests/marker-resolver.bats`
- `tests/repl-invoke-shim.bats`
- `tests/stop-gate.bats`
- `tests/live-session-smoke.bats`

Suggested Cline test files:

- `tests/manifest.test.ts`
- `tests/marker-resolver.test.ts`
- `tests/repl-bridge.test.ts`
- `tests/session-shim.test.ts`
- `tests/todo.test.ts`
- `tests/requirements.test.ts`
- `tests/graphrag.test.ts`
- `tests/cache-manager.test.ts`
- `tests/live-session-smoke.test.ts`

## Cross-Plugin Harness Design

Create a small harness that accepts:

- `pluginName`
- `pluginRoot`
- `agentName`
- `sessionPrefix`
- `workspacePath`
- `markerPath`
- `serverBaseUrl`
- `apiKey`
- `runtimeKind`

Runtime kinds:

- `codex-shell`
- `claude-shell`
- `claude-powershell`
- `copilot-shell`
- `cline-node`

Harness responsibilities:

1. Create isolated temp workspace.
2. Generate a trusted marker.
3. Stub `mcpserver-repl` when running offline tests.
4. Stub `curl` and `openssl` for deterministic trust tests.
5. Run plugin start command.
6. Run prompt hook or tool.
7. Run workflow command.
8. Query live server when in live mode.
9. Record JSON evidence.
10. Clean up temp files.

Evidence output should be one directory per run:

- `run.json`
- `commands.log`
- `stdout.log`
- `stderr.log`
- `session-state.yaml`
- `current-turn.yaml`
- `server-readback.json`
- `git-status.txt`
- `environment.txt`

## Live Test Workspace Requirements

Use a disposable workspace such as:

- `F:\GitHub\McpPluginValidationWorkspace`

Required files:

- `AGENTS-README-FIRST.yaml`
- `AGENTS.md`
- `docs/todo.yaml` only if needed by the server workspace configuration
- a minimal source file for code verification
- a minimal test command that can pass and fail deterministically

The workspace should include a validation script:

```bash
#!/usr/bin/env bash
set -euo pipefail
if [ -f fail-build.marker ]; then
  echo "intentional failure"
  exit 1
fi
echo "validation passed"
```

This lets the code verification tests control pass/fail behavior without relying on unrelated project builds.

## Required Evidence Checklist

Every validation run must record:

1. Plugin repository path.
2. Plugin commit SHA.
3. Plugin dirty status.
4. Plugin version.
5. Agent name.
6. Host runtime and shell.
7. McpServer base URL.
8. Workspace path.
9. Marker file timestamp.
10. Signature verification result.
11. Health nonce and echo.
12. Session ID.
13. Request ID.
14. Test command list.
15. Test exit codes.
16. Server readback result.
17. Stop gate result.
18. Any pending cache files.
19. Any cleanup actions.
20. Any known failures or skipped tests.

## Release Gate

A plugin is releasable only when all of the following are true:

1. Static manifest tests pass.
2. Syntax/build tests pass.
3. Marker trust tests pass.
4. REPL workflow shim tests pass.
5. Session lifecycle tests pass.
6. Hook enforcement tests pass.
7. TODO tests pass.
8. Requirements tests pass.
9. GraphRAG tests pass or are explicitly unsupported with a documented reason.
10. Offline cache tests pass.
11. Live session smoke test passes.
12. Cross-plugin parity scenario passes for all four plugins.
13. Server readback confirms every live session test.
14. No test-generated cache or workspace artifacts are left dirty unless intentionally kept as evidence.
15. The final validation report names all skipped tests and why they were skipped.

## Failure Triage Rules

When a test fails:

1. Preserve the first failing stdout, stderr, cache files, and server response.
2. Classify the failure as marker, auth, transport, serialization, identity, workflow, cache, hook, server, or host integration.
3. Reproduce with the smallest command that still fails.
4. Verify whether the failure is Codex-only or cross-plugin.
5. If the failure is cross-plugin, fix the shared pattern first and port it.
6. If the failure is host-specific, add a host-specific regression test.
7. Never call a server readback empty result a success when the expected session or artifact is absent.
8. Never treat local cache state as proof of server persistence.
9. Do not repair by substituting raw REST for a plugin path unless the test is explicitly diagnosing plugin failure.

## Minimum Commands for Current Codex Plugin

From `F:\GitHub\mcpserver-codex-plugin`:

```powershell
git -c safe.directory=F:/GitHub/mcpserver-codex-plugin status --short --branch
```

```bash
bash -n lib/cache-manager.sh lib/code-verify.sh lib/ensure-repl.sh lib/marker-resolver.sh lib/repl-invoke.sh lib/session-start.sh lib/stop-gate.sh lib/user-prompt-submit.sh
```

```bash
bats --tap tests/session-start.bats
bats --tap tests/user-prompt-submit.bats
bats --tap tests/stop-gate.bats
bats --tap tests/code-verify.bats
bats --tap tests/repl-invoke-shim.bats
```

Focused auth regression:

```bash
bats --tap -f "workflow.sessionlog.queryHistory" tests/repl-invoke-shim.bats
```

Live LlamaDeck-style queryHistory smoke:

```bash
cd /f/GitHub/LlamaDeck
export CODEX_PLUGIN_ROOT=/f/GitHub/mcpserver-codex-plugin
export PLUGIN_AGENT_NAME=Codex
export MCP_SESSION_AGENT=Codex
export MCP_SESSION_MODEL=GPT-5
printf 'agent: Codex\nlimit: 10\noffset: 0\n' \
  | "$CODEX_PLUGIN_ROOT/lib/repl-invoke.sh" workflow.sessionlog.queryHistory
```

Expected live smoke result:

- Exit code `0`.
- No `Authentication required`.
- No `method_not_found`.
- If result body is empty, perform separate server readback before claiming persistence.

## Minimum Commands for Sibling Plugins

Claude Code:

```bash
cd /f/GitHub/mcpserver-claude-code-plugin
bash -n hooks/scripts/*.sh lib/*.sh
bats --tap tests/
```

```powershell
cd F:\GitHub\mcpserver-claude-code-plugin
pwsh -NoLogo -NoProfile -File tests/repl-invoke-shim.ps1.tests.ps1
```

Copilot:

```bash
cd /f/GitHub/mcpserver-copilot-plugin
bash -n hooks/scripts/*.sh lib/*.sh
bats --tap tests/
```

Cline:

```bash
cd /f/GitHub/mcpserver-cline-plugin
npm ci
npm run build
npm test
```

## Final Validation Report Template

Use this structure for the validation report.

```text
Plugin validation report

Date:
Tester:
McpServer base URL:
Workspace:
Marker timestamp:

Plugin:
Repository:
Commit:
Dirty status:
Version:
Agent identity:

Commands run:
- command:
  exit code:
  result:

Session evidence:
- session ID:
- request ID:
- server readback:
- stop gate:

Functional evidence:
- TODO:
- session log:
- requirements:
- GraphRAG:
- cache:
- enforcement:

Cross-plugin parity:
- Codex:
- Claude Code:
- Copilot:
- Cline:

Failures:
- ID:
  classification:
  exact error:
  reproduction:
  owner:
  next step:

Skipped tests:
- ID:
  reason:
  risk:

Conclusion:
```

## Immediate Next Steps

1. Add the missing manifest/static validation tests to Codex first.
2. Stabilize the full Codex Bats suite so existing requirements tests do not hang.
3. Extract shared marker and fake REPL fixtures from Codex tests.
4. Port the auth-sensitive `queryHistory` regression to Claude Code and Copilot.
5. Add the equivalent Cline Jest regression around `src/transport/repl-bridge.ts` and `src/tools/session-shim.ts`.
6. Build the cross-plugin harness and run the parity scenario against all four local repos.
7. Only after automated parity passes, run manual host integration validation.
