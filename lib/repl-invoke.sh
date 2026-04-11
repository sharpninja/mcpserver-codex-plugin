#!/usr/bin/env bash
set -euo pipefail

# repl_invoke <method> [params_yaml]
# Sends a YAML request envelope to mcpserver-repl --agent-stdio
# Returns the response payload on stdout, exit 1 on error

REPL_INVOKE_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

repl_invoke() {
    local method="$1"
    local params_yaml="${2:-}"
    local request_id="req-$(date -u +%Y%m%dT%H%M%SZ)-$(printf '%04x' $RANDOM)"
    local timeout="${REPL_TIMEOUT:-30}"

    if ! command -v mcpserver-repl >/dev/null 2>&1; then
        echo "ERROR: mcpserver-repl not found on PATH" >&2
        return 1
    fi

    # Construct YAML envelope
    local envelope="type: request
payload:
  requestId: ${request_id}
  method: ${method}"

    if [ -n "$params_yaml" ]; then
        local indented_params
        indented_params=$(echo "$params_yaml" | sed 's/^/    /')
        envelope="${envelope}
  params:
${indented_params}"
    fi

    # Pipe to mcpserver-repl and capture response
    local response
    if response=$(echo "$envelope" | timeout "$timeout" mcpserver-repl --agent-stdio 2>/dev/null); then
        echo "$response"
        return 0
    else
        echo "ERROR: mcpserver-repl invocation failed for method ${method}" >&2
        return 1
    fi
}

# Build envelope without sending (for testing/cache)
repl_build_envelope() {
    local method="$1"
    local params_yaml="${2:-}"
    local request_id="req-$(date -u +%Y%m%dT%H%M%SZ)-$(printf '%04x' $RANDOM)"

    local envelope="type: request
payload:
  requestId: ${request_id}
  method: ${method}"

    if [ -n "$params_yaml" ]; then
        local indented_params
        indented_params=$(echo "$params_yaml" | sed 's/^/    /')
        envelope="${envelope}
  params:
${indented_params}"
    fi

    echo "$envelope"
}

export -f repl_invoke repl_build_envelope 2>/dev/null || true
