---
name: Per-Turn Enforcement Protocol
description: Required workflow for every user message in a Codex session. Opens a session log turn, logs all code edits, verifies builds, and closes the turn before responding. Use EVERY user message — this is not optional.
---

## Overview

Codex CLI lacks a hook system, so the Per-User-Message protocol from
`AGENTS-README-FIRST.yaml` must be invoked manually. This skill wraps that
protocol in three scripts located in the plugin's `lib/` directory.

Run `PowerShell ${CODEX_PLUGIN_ROOT}/lib/session-start.ps1 <workspace-path>` once per
workspace before Phase 1, or let `user-prompt-submit.ps1` auto-bootstrap the
session cache on first use. Runtime state is scoped under
`cache/workspaces/<workspace-key>/sessions/<session-key>/`.

**Every user message MUST flow through these three phases.** If you skip any
phase your session log is incomplete and the workspace's AGENTS-README-FIRST
contract is violated.

## Phase 1 — Open a Turn (before any tool call)

Invoke on every new user prompt **before** calling any other tool:

```powershell
echo '{"prompt":"<verbatim user message>"}' | PowerShell ${CODEX_PLUGIN_ROOT}/lib/user-prompt-submit.ps1
```

The script:
- Auto-bootstraps scoped `session-state.yaml` when the marker file is trusted
- Reads scoped `session-state.yaml` for the active `sessionId`
- Builds a fresh `requestId` of the form `req-<yyyyMMddTHHmmssZ>-prompt-xxxx`
- Calls `workflow.sessionlog.beginTurn` with the prompt as `queryText`
- Writes scoped `current-turn.yaml` with `turnRequestId`, `codeEdits: 0`,
  `lastBuildStatus: unknown`, `status: in_progress`
- Emits a reminder via `additionalContext` that Phases 2 and 3 are mandatory

If the script outputs `status: no-session`, do not treat that as a final best-effort state. The hook has already health-checked the marker, attempts session creation when the marker timestamp changes, submits triage if creation fails after a healthy bootstrap, and records degraded recovery state under the failsafe path. Continue the user request, but preserve the `recoveryStatus`, `healthStatus`, and `failsafePath` receipt as evidence; retry session creation only after `AGENTS-README-FIRST.yaml` is rewritten or the hook reports recovery.

## Phase 2 — After Every Code Edit

Immediately after you write or edit any source file
(`.cs`, `.axaml`, `.xaml`, `.csproj`, `.fsproj`, `.vbproj`, `.razor`,
`.cshtml`, `.ts`, `.tsx`, `.js`, `.jsx`) invoke:

```powershell
echo '{"tool_name":"Edit","tool_input":{"file_path":"<absolute path>"}}' \
  | PowerShell ${CODEX_PLUGIN_ROOT}/lib/code-verify.ps1
```

The script:
- Locates the nearest project file (`.csproj` / `package.json`)
- Runs the matching build command (`dotnet build` or `tsc --noEmit`)
- Parses the output and writes the status (`succeeded` / `failed`) to
  scoped `current-turn.yaml` under `lastBuildStatus`
- Records the code edit count via `workflow.sessionlog.appendActions`
- Appends a `workflow.sessionlog.appendActions` entry
- If the build failed, its stdout contains the first 10 errors; those
  errors are the reason you must fix the build before Phase 3

**Do not move on to the next edit or close the turn while
`lastBuildStatus: failed` is cached.** Fix the errors first.

## Phase 3 — Close the Turn (before your final response)

Before emitting your response to the user, invoke:

```powershell
PowerShell ${CODEX_PLUGIN_ROOT}/lib/stop-gate.ps1
```

The script checks scoped `current-turn.yaml` and returns `decision: block`
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

Then re-run `stop-gate.ps1`. Repeat until it returns `status: passed`.

If the build is intentionally left broken (rare), touch
scoped `turn-accept-failure.marker` *before* the next `stop-gate.ps1` call;
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
and update the current session's scoped `current-turn.yaml` which is created
in Phase 1 and consumed by Phase 3. The scoped cache is the source of truth
for turn state — never infer turn status from memory or conversation.

## See Also

- `skills/session/SKILL.md` — raw `workflow.sessionlog.*` commands
- `skills/todo/SKILL.md` — TODO management
- `AGENTS-README-FIRST.yaml` (workspace root) — authoritative contract
