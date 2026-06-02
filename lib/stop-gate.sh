#!/usr/bin/env bash
# stop-gate.sh — Stop hook for the McpServer Codex plugin.
#
# Runs when Codex is about to finalize its response. Verifies that the
# active session log turn (opened by user-prompt-submit.sh) was completed
# with actions recorded. If not, blocks Stop and returns a reason so Codex
# continues and fulfills the protocol.
#
# Additional gate: if the turn cache marks lastBuildStatus=failed after a
# code edit in this turn, Stop is blocked until a successful build is recorded
# OR the agent explicitly sets an "accepted-failure" flag.
#
# Input (stdin): Codex Stop payload.
# Output (stdout): JSON. When blocking returns {"decision":"block","reason":"..."}.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODEX_PLUGIN_ROOT="${CODEX_PLUGIN_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"

if [ -f "$CODEX_PLUGIN_ROOT/lib/cache-scope.sh" ]; then
    # shellcheck source=./cache-scope.sh
    source "$CODEX_PLUGIN_ROOT/lib/cache-scope.sh"
    cache_scope_init "$CODEX_PLUGIN_ROOT" "$PWD"
else
    CACHE_DIR="${PLUGIN_ROOT_OVERRIDE:-$CODEX_PLUGIN_ROOT}/cache"
fi

# Thin v4 core shim (Phase 2 Codex demo)
# shellcheck source=./core-shim.sh
source "$CODEX_PLUGIN_ROOT/lib/core-shim.sh" 2>/dev/null || true
TURN_FILE="$CACHE_DIR/current-turn.yaml"

# Read stdin (may be empty) so the hook runtime doesn't complain about an unread pipe.
cat >/dev/null 2>&1 || true

# Avoid re-prompting loops: if the hook runtime already set stop_hook_active=true
# on a previous block, let this Stop through. Keep the existing env var name for
# compatibility with the host runtime.
STOP_HOOK_ACTIVE="${CLAUDE_STOP_HOOK_ACTIVE:-false}"
if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
    # Allow the stop. Claude Code's Stop schema rejects a hookSpecificOutput
    # that carries a custom "status" field ("(root): Invalid input"); an empty
    # object is the canonical schema-valid "allow, stay quiet" output.
    printf '{}\n'
    exit 0
fi

# No turn file = no gate (e.g. MCP was unavailable; no enforcement possible).
if [ ! -f "$TURN_FILE" ]; then
    printf '{}\n'
    exit 0
fi

TURN_STATUS="$(grep '^status:' "$TURN_FILE" 2>/dev/null | head -1 | sed 's/^status:[[:space:]]*//')"
TURN_ID="$(grep '^turnRequestId:' "$TURN_FILE" 2>/dev/null | head -1 | sed 's/^turnRequestId:[[:space:]]*//')"
BUILD_STATUS="$(grep '^lastBuildStatus:' "$TURN_FILE" 2>/dev/null | head -1 | sed 's/^lastBuildStatus:[[:space:]]*//')"
CODE_EDITS="$(grep '^codeEdits:' "$TURN_FILE" 2>/dev/null | head -1 | sed 's/^codeEdits:[[:space:]]*//')"
CODE_EDITS="${CODE_EDITS:-0}"

# Gate 1 — turn not completed.
# Self-heal: agents may not be able to reach workflow.sessionlog.* (not
# registered in the MCP tool surface); auto-complete the turn here so Stop
# is not wedged. Fall through to the explicit block only if self-heal fails.
if [ "$TURN_STATUS" = "in_progress" ]; then
    if [ -f "$CODEX_PLUGIN_ROOT/lib/repl-invoke.sh" ]; then
        # shellcheck source=./repl-invoke.sh
        source "$CODEX_PLUGIN_ROOT/lib/repl-invoke.sh" 2>/dev/null || true
    fi
    if type v4_complete_turn >/dev/null 2>&1; then
        # Delegate self-heal to v4 shim (maps to IV4EnforcementStateMachine.CompleteTurnAsync)
        v4_complete_turn "$TURN_ID" "true" >/dev/null 2>&1 || true
        TURN_STATUS="$(grep '^status:' "$TURN_FILE" 2>/dev/null | head -1 | sed 's/^status:[[:space:]]*//')"
    elif type _repl_workflow_complete_turn >/dev/null 2>&1; then
        AUTO_PARAMS="response: |
    Auto-closed by stop-gate.sh (turn self-heal). The agent could not invoke workflow.sessionlog.* directly; the hook now finalizes the turn when the response finishes."
        PREVIOUS_REPL_TIMEOUT="${REPL_TIMEOUT:-}"
        export REPL_TIMEOUT="${REPL_SESSIONLOG_REPL_TIMEOUT:-8}"
        _repl_workflow_complete_turn "$AUTO_PARAMS" >/dev/null 2>&1 || true
        if [ -n "$PREVIOUS_REPL_TIMEOUT" ]; then
            export REPL_TIMEOUT="$PREVIOUS_REPL_TIMEOUT"
        else
            unset REPL_TIMEOUT
        fi
        TURN_STATUS="$(grep '^status:' "$TURN_FILE" 2>/dev/null | head -1 | sed 's/^status:[[:space:]]*//')"
    fi
    if [ "$TURN_STATUS" = "in_progress" ]; then
        REASON="Session log turn ${TURN_ID} could not be auto-closed. Check plugin/lib/repl-invoke.sh or MCP server availability."
        printf '{"decision":"block","reason":"%s"}\n' "$REASON"
        exit 0
    fi
fi

# Gate 2 — build broken after a code edit.
if [ "$CODE_EDITS" -gt 0 ] && [ "$BUILD_STATUS" = "failed" ]; then
    REASON="Last build in this turn failed after ${CODE_EDITS} code edit(s). Fix the build errors before claiming done, or explicitly accept failure by writing the scoped turn-accept-failure.marker."
    if [ -f "$CACHE_DIR/turn-accept-failure.marker" ]; then
        rm -f "$CACHE_DIR/turn-accept-failure.marker"
    else
        printf '{"decision":"block","reason":"%s"}\n' "$REASON"
        exit 0
    fi
fi

# Gate 3 — session-log audit completeness after code edits (PLAN-SESSIONLOGENFORCEMENT-001).
# A turn that changed code must record at least one action, one modified file, and one
# reasoning/decision dialog entry so completed turns are not finalized with empty audit
# data. Enforced only when the turn carries the audit schema (auditActions present); turn
# caches that predate the audit fields are exempt and remain backward compatible.
if grep -q '^auditActions:' "$TURN_FILE" 2>/dev/null && [ "$CODE_EDITS" -gt 0 ]; then
    AUDIT_ACTIONS="$(grep '^auditActions:' "$TURN_FILE" | head -1 | sed 's/^auditActions:[[:space:]]*//')"
    AUDIT_FILES="$(grep '^auditFiles:' "$TURN_FILE" | head -1 | sed 's/^auditFiles:[[:space:]]*//')"
    AUDIT_DIALOG="$(grep '^auditDialog:' "$TURN_FILE" | head -1 | sed 's/^auditDialog:[[:space:]]*//')"
    AUDIT_DECISIONS="$(grep '^auditDecisions:' "$TURN_FILE" | head -1 | sed 's/^auditDecisions:[[:space:]]*//')"
    AUDIT_ACTIONS="${AUDIT_ACTIONS:-0}"
    AUDIT_FILES="${AUDIT_FILES:-0}"
    AUDIT_DIALOG="${AUDIT_DIALOG:-0}"
    AUDIT_DECISIONS="${AUDIT_DECISIONS:-0}"
    MISSING=""
    [ "$AUDIT_ACTIONS" -ge 1 ] 2>/dev/null || MISSING="${MISSING} actions"
    [ "$AUDIT_FILES" -ge 1 ] 2>/dev/null || MISSING="${MISSING} filesModified"
    if ! { [ "$AUDIT_DIALOG" -ge 1 ] 2>/dev/null || [ "$AUDIT_DECISIONS" -ge 1 ] 2>/dev/null; }; then
        MISSING="${MISSING} processingDialog/designDecisions"
    fi
    if [ -n "$MISSING" ]; then
        if [ -f "$CACHE_DIR/turn-accept-incomplete-audit.marker" ]; then
            rm -f "$CACHE_DIR/turn-accept-incomplete-audit.marker"
        else
            REASON="Turn ${TURN_ID} made ${CODE_EDITS} code edit(s) but the session-log audit is incomplete (missing:${MISSING}). Record them with workflow.sessionlog.appendActions and appendDialog (or workflow.sessionlog.closeTurn), or write the scoped turn-accept-incomplete-audit.marker to accept."
            printf '{"decision":"block","reason":"%s"}\n' "$REASON"
            exit 0
        fi
    fi
fi

# All gates passed. Emit the canonical schema-valid no-op (allow the stop).
printf '{}\n'
exit 0
