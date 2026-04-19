#!/usr/bin/env bash
# code-verify.sh — PostToolUse (Write|Edit) hook for the McpServer plugin.
#
# Runs after every Write/Edit. If the edited file is a buildable source file
# (.cs / .axaml / .csproj / .vbproj / .fsproj / .ts / .tsx), locates the
# nearest project/solution and runs a verification command. Injects build
# errors as additionalContext so Claude sees them, and updates cache/current-turn.yaml
# with lastBuildStatus so the Stop hook can gate finalization.
#
# Also appends a session log action via workflow.sessionlog.appendActions so
# the edit is part of the turn's action record.
#
# Input (stdin): Claude Code PostToolUse payload with tool_name + tool_input.
# Output (stdout): JSON with additionalContext on build failure.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODEX_PLUGIN_ROOT="${CODEX_PLUGIN_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
CACHE_DIR="${PLUGIN_ROOT_OVERRIDE:-$CODEX_PLUGIN_ROOT}/cache"
TURN_FILE="$CACHE_DIR/current-turn.yaml"

# Source libraries best-effort
if ! type repl_invoke >/dev/null 2>&1; then
    source "$CODEX_PLUGIN_ROOT/lib/repl-invoke.sh" 2>/dev/null || true
fi

PAYLOAD="$(cat 2>/dev/null || true)"

# Extract file_path from tool_input. Prefer jq when available.
extract_file_path() {
    if command -v jq >/dev/null 2>&1; then
        printf '%s' "$PAYLOAD" | jq -r '.tool_input.file_path // empty' 2>/dev/null
    else
        printf '%s' "$PAYLOAD" | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1
    fi
}

FILE_PATH="$(extract_file_path)"
if [ -z "$FILE_PATH" ] || [ ! -f "$FILE_PATH" ]; then
    printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","status":"skipped","reason":"no file"}}\n'
    exit 0
fi

# Only verify source files.
EXT="${FILE_PATH##*.}"
case "$EXT" in
    cs|axaml|xaml|csproj|vbproj|fsproj|razor|cshtml)
        VERIFY_KIND="dotnet"
        ;;
    ts|tsx|js|jsx)
        VERIFY_KIND="node"
        ;;
    *)
        printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","status":"skipped","reason":"unsupported-ext","ext":"%s"}}\n' "$EXT"
        exit 0
        ;;
esac

# ─── Find nearest project file ───────────────────────────────────────────
find_nearest_project() {
    local start="$1"
    local dir
    dir="$(dirname "$start")"
    while [ "$dir" != "/" ] && [ "$dir" != "." ] && [ -n "$dir" ]; do
        case "$VERIFY_KIND" in
            dotnet)
                local candidate
                candidate="$(find "$dir" -maxdepth 1 -name '*.csproj' -o -maxdepth 1 -name '*.fsproj' -o -maxdepth 1 -name '*.vbproj' 2>/dev/null | head -1)"
                if [ -n "$candidate" ]; then
                    printf '%s' "$candidate"
                    return 0
                fi
                ;;
            node)
                if [ -f "$dir/package.json" ]; then
                    printf '%s' "$dir/package.json"
                    return 0
                fi
                ;;
        esac
        dir="$(dirname "$dir")"
    done
    return 1
}

PROJECT="$(find_nearest_project "$FILE_PATH" || true)"

if [ -z "$PROJECT" ]; then
    printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","status":"skipped","reason":"no-project-found"}}\n'
    exit 0
fi

# ─── Run verify command ──────────────────────────────────────────────────
BUILD_LOG="$CACHE_DIR/last-build.log"
mkdir -p "$CACHE_DIR"

run_verify() {
    case "$VERIFY_KIND" in
        dotnet)
            # --nologo quiets header; -clp:NoSummary strips summary block
            dotnet build "$PROJECT" --nologo -clp:NoSummary 2>&1
            ;;
        node)
            # Prefer tsc --noEmit when tsconfig present, else skip
            local proj_dir
            proj_dir="$(dirname "$PROJECT")"
            if [ -f "$proj_dir/tsconfig.json" ] && command -v npx >/dev/null 2>&1; then
                (cd "$proj_dir" && npx -y tsc --noEmit 2>&1)
            else
                echo "skipped: no tsconfig.json or npx"
                return 0
            fi
            ;;
    esac
}

BUILD_OUT="$(run_verify || echo "__BUILD_FAILED_SENTINEL__")"
BUILD_EXIT=$?

# run_verify returns 0 on success. We ran it via subshell so capture via sentinel.
if printf '%s' "$BUILD_OUT" | grep -q '__BUILD_FAILED_SENTINEL__'; then
    BUILD_STATUS="failed"
else
    # Dotnet returns 0 even when Build Succeeded; check for "Build FAILED"
    if printf '%s' "$BUILD_OUT" | grep -qi "Build FAILED\|error CS\|error AVLN"; then
        BUILD_STATUS="failed"
    else
        BUILD_STATUS="succeeded"
    fi
fi

printf '%s\n' "$BUILD_OUT" > "$BUILD_LOG"

# ─── Update current-turn.yaml ────────────────────────────────────────────
if [ -f "$TURN_FILE" ]; then
    # Increment codeEdits + set lastBuildStatus (portable sed)
    CURRENT_EDITS="$(grep '^codeEdits:' "$TURN_FILE" | head -1 | sed 's/^codeEdits:[[:space:]]*//')"
    CURRENT_EDITS="${CURRENT_EDITS:-0}"
    NEW_EDITS=$((CURRENT_EDITS + 1))
    # Rewrite file (sed -i differs across platforms; use temp file)
    TMP="$(mktemp)"
    awk -v edits="$NEW_EDITS" -v status="$BUILD_STATUS" '
        /^codeEdits:/ { print "codeEdits: " edits; next }
        /^lastBuildStatus:/ { print "lastBuildStatus: " status; next }
        { print }
    ' "$TURN_FILE" > "$TMP" && mv "$TMP" "$TURN_FILE"
fi

# ─── Append session log action ───────────────────────────────────────────
if type repl_invoke >/dev/null 2>&1 && [ -f "$TURN_FILE" ]; then
    TURN_ID="$(grep '^turnRequestId:' "$TURN_FILE" | head -1 | sed 's/^turnRequestId:[[:space:]]*//')"
    if [ -n "$TURN_ID" ]; then
        ACTION_PARAMS="actions:
  - order: 1
    description: \"Auto-logged Edit/Write of ${FILE_PATH} (build ${BUILD_STATUS})\"
    type: edit
    status: completed
    filePath: \"${FILE_PATH}\""
        repl_invoke "workflow.sessionlog.appendActions" "$ACTION_PARAMS" >/dev/null 2>&1 || true
    fi
fi

# ─── Output ──────────────────────────────────────────────────────────────
if [ "$BUILD_STATUS" = "failed" ]; then
    # First 2000 chars of build output to keep context bounded
    ERRORS="$(printf '%s' "$BUILD_OUT" | grep -iE 'error (CS|AVLN|MSB)' | head -10)"
    [ -z "$ERRORS" ] && ERRORS="$(printf '%s' "$BUILD_OUT" | tail -20)"
    # JSON-escape newlines + quotes
    ERRORS_JSON="$(printf '%s' "$ERRORS" | awk 'BEGIN{ORS="\\n"} {gsub(/"/, "\\\""); print}')"
    MSG="Build FAILED after edit to ${FILE_PATH}. Fix before continuing:\\n${ERRORS_JSON}"
    printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","status":"build-failed","additionalContext":"%s"}}\n' "$MSG"
else
    printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","status":"build-%s","project":"%s"}}\n' "$BUILD_STATUS" "$PROJECT"
fi
exit 0
