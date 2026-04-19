---
name: Per-Turn Enforcement Protocol
description: Required workflow for every user message in a Codex session. Opens a session log turn, logs all code edits, verifies builds, and closes the turn before responding. Use EVERY user message — this is not optional.
---

## Overview

Codex CLI lacks a hook system, so the Per-User-Message protocol from
`AGENTS-README-FIRST.yaml` must be invoked manually. This skill wraps that
protocol in three scripts located in the plugin's `lib/` directory.

**Every user message MUST flow through these three phases.** If you skip any
phase your session log is incomplete and the workspace's AGENTS-README-FIRST
contract is violated.

## Phase 1 — Open a Turn (before any tool call)

Invoke on every new user prompt **before** calling any other tool:

```bash
echo '{"prompt":"<verbatim user message>"}' | bash ${CODEX_PLUGIN_ROOT}/lib/user-prompt-submit.sh
```

The script:
- Reads `cache/session-state.yaml` for the active `sessionId`
- Builds a fresh `requestId` of the form `req-<yyyyMMddTHHmmssZ>-prompt-xxxx`
- Calls `workflow.sessionlog.beginTurn` with the prompt as `queryText`
- Writes `cache/current-turn.yaml` with `turnRequestId`, `codeEdits: 0`,
  `lastBuildStatus: unknown`, `status: in_progress`
- Emits a reminder via `additionalContext` that Phases 2 and 3 are mandatory

If the script output `status: no-session`, MCP is unavailable; continue best-effort
without session logging, but still fulfill the user request.

## Phase 2 — After Every Code Edit

Immediately after you write or edit any source file
(`.cs`, `.axaml`, `.xaml`, `.csproj`, `.fsproj`, `.vbproj`, `.razor`,
`.cshtml`, `.ts`, `.tsx`, `.js`, `.jsx`) invoke:

```bash
echo '{"tool_name":"Edit","tool_input":{"file_path":"<absolute path>"}}' \
  | bash ${CODEX_PLUGIN_ROOT}/lib/code-verify.sh
```

The script:
- Locates the nearest project file (`.csproj` / `package.json`)
- Runs the matching build command (`dotnet build` or `tsc --noEmit`)
- Parses the output, writes the status (`succeeded` / `failed`) to
  `cache/current-turn.yaml` under `lastBuildStatus`, increments `codeEdits`
- Appends a `workflow.sessionlog.appendActions` entry
- If the build failed, its stdout contains the first 10 errors; those
  errors are the reason you must fix the build before Phase 3

**Do not move on to the next edit or close the turn while
`lastBuildStatus: failed` is cached.** Fix the errors first.

## Phase 3 — Close the Turn (before your final response)

Before emitting your response to the user, invoke:

```bash
bash ${CODEX_PLUGIN_ROOT}/lib/stop-gate.sh
```

The script checks `cache/current-turn.yaml` and returns `decision: block`
with a reason in any of these cases:
- `status: in_progress` — you forgot to call `workflow.sessionlog.completeTurn`
- `codeEdits > 0 && lastBuildStatus = failed` — build is broken

When blocked, finish the missing step:

```yaml
# Complete the turn
type: request
payload:
  requestId: req-<new-id>
  method: workflow.sessionlog.completeTurn
  params:
    response: |
      <one-paragraph summary of what was delivered>
```

Then re-run `stop-gate.sh`. Repeat until it returns `status: passed`.

If the build is intentionally left broken (rare), touch
`cache/turn-accept-failure.marker` *before* the next `stop-gate.sh` call;
the script consumes the marker on its next pass.

## Contract

This protocol exists because:
- `AGENTS-README-FIRST.yaml` Rule 2 requires a session log turn per user message
- `AGENTS-README-FIRST.yaml` Rule 10 requires you to verify code compiles
- `AGENTS-README-FIRST.yaml` "Before Delivering Output" requires the session
  log to be current before you respond

Skipping any phase leaves the contract broken. If you forget mid-turn,
invoke the missing phase as soon as you notice; partial compliance beats none.

## Integration With Your Workflow

The three scripts are idempotent for the lifetime of one turn. They read
and update `cache/current-turn.yaml` which is created in Phase 1 and
consumed by Phase 3. `cache/` is the source of truth for turn state —
never infer turn status from memory or conversation.

## See Also

- `skills/session/SKILL.md` — raw `workflow.sessionlog.*` commands
- `skills/todo/SKILL.md` — TODO management
- `AGENTS-README-FIRST.yaml` (workspace root) — authoritative contract
