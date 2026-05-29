# McpServer Codex Plugin - Enforcement Protocol (v4)

This plugin implements the McpServer **v4 Shared Enforcement Protocol** for Codex agent sessions.

## Shared Core Reference

All enforcement behaviors align with the canonical v4 shared core defined in:
- `packages/mcpserver-agent-core` (`@sharpninja/mcpserver-agent-core`)
- `docs/plans/plan-agent-plugin-operational-parity-v1.0.md` in the McpServer repository
- TR-MCP-AGENT-PARITY-010 through -013 (technical requirements for shared enforcement)

## Three-Phase Protocol

Every user message triggers the v4 three-phase enforcement protocol:

### Phase 1 - Begin Turn (`user-prompt-submit.sh`)
- `lib/user-prompt-submit.sh` calls `workflow.sessionlog.beginTurn` via REPL
- A `current-turn.yaml` file is written to the workspace cache so the stop gate can verify completion
- If the server is unavailable, the turn is buffered to the v4 failsafe cache

### Phase 2 - Edit + Verify (`code-verify.sh`)
- `lib/code-verify.sh` runs the project build after every file edit
- Build failure transitions the enforcement state to `BlockedOnBuild`
- Build success is recorded in the session log action list (`appendActions`)

### Phase 3 - Complete Turn (`stop-gate.sh`)
- `lib/stop-gate.sh` verifies the turn was begun and not left open
- If a prior build failed, the stop gate blocks the response (no escape hatch)
- Successful completion calls `workflow.sessionlog.completeTurn`
- If server is unavailable, the completion is buffered to failsafe cache

## State Machine

The enforcement states (per v4 shared core, TR-MCP-AGENT-PARITY-011):

```
NoTurn
  |-- user-prompt-submit --> TurnOpen
       |-- code-verify (success) --> EditsInProgress
       |-- code-verify (failure) --> BlockedOnBuild (no escape, stop gate blocked)
       |-- stop-gate (all builds green) --> TurnComplete
       |-- stop-gate (pending edits, no complete) --> BlockedOnMissingComplete
```

## Failsafe Cache (v4 format, TR-MCP-AGENT-PARITY-013)

When the MCP server is unavailable, pending REPL calls are buffered to the workspace failsafe cache:

**v4 layout:** `<workspace_root>/.mcpServer/failsafe/Codex/workspaces/<base64url(workspacePath)>/`
- `pending/` - queued entries, max 3 retries
- `failed/` - entries exceeding retry limit

The workspace key is the Base64URL encoding of the absolute workspace path, matching
`V4CacheManager.GetScopedCachePath` in `@sharpninja/mcpserver-agent-core`.

**Legacy layout** (pre-v4): `cache/workspaces/<slug-sha1>/sessions/<session-key>/` remains
supported for read-back during migration. New writes use the v4 layout.

## Marker Bootstrap (TR-MCP-AGENT-PARITY-012)

`lib/marker-resolver.sh` implements upward directory search for `AGENTS-README-FIRST.yaml`,
HMAC-SHA256 signature verification with the workspace API key, and nonce health challenge
against `/health?nonce=`. Behavior is identical to `V4MarkerTrustService` in the shared core.

## Plugin Version

This plugin is on the v1.x operational parity release line. All eight official `mcpserver-*-plugin`
repositories share this enforcement protocol version.

## Agent Identity

This plugin targets the `Codex` agent (`sourceType: Codex`). Session IDs use the prefix
`Codex-<yyyyMMddTHHmmssZ>-<suffix>`. The required env var is `CODEX_PLUGIN_ROOT`.

## References

- `.codex-plugin/plugin.json` - Codex-native plugin descriptor and activation
- `lib/session-start.sh` - session initialization
- `lib/user-prompt-submit.sh` - begin-turn enforcement
- `lib/stop-gate.sh` - complete-turn enforcement gate
- `lib/code-verify.sh` - build verification after edits
- `lib/cache-scope.sh` - workspace key derivation (v4: `cache_scope_workspace_key_v4`, `cache_scope_v4_failsafe_root`)
- `lib/cache-manager.sh` - pending write/flush/recovery (MAX_RETRIES=3)
- `lib/marker-resolver.sh` - HMAC-SHA256 marker trust
- `lib/repl-invoke.sh` - REPL client with retry and timeout
- `lib/subagent-import.sh` - subagent transcript capture
