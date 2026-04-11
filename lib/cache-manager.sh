#!/usr/bin/env bash
set -euo pipefail

# Local write cache for MCP operations when server is unavailable.
# Pending commands are stored as YAML files and replayed via repl_invoke.

CACHE_MANAGER_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CACHE_MANAGER_PLUGIN_ROOT="${PLUGIN_ROOT_OVERRIDE:-$(cd "$CACHE_MANAGER_SCRIPT_DIR/.." && pwd)}"
CACHE_DIR="${CACHE_MANAGER_PLUGIN_ROOT}/cache"
PENDING_DIR="${CACHE_DIR}/pending"
MAX_RETRIES=3

_ensure_cache_dirs() {
    mkdir -p "$PENDING_DIR"
}

# cache_write <method> [params_yaml]
# Saves a pending REPL command as a YAML file in cache/pending/
# Outputs the path to the created file
cache_write() {
    local method="$1"
    local params_yaml="${2:-}"
    _ensure_cache_dirs

    # Monotonic sequence: count existing files + 1
    local count
    count=$(find "$PENDING_DIR" -maxdepth 1 -name '*.yaml' 2>/dev/null | wc -l | tr -d ' ')
    local seq
    seq=$(printf '%03d' $(( count + 1 )))

    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    local slug
    slug=$(echo "$method" | tr '.' '-')
    local filename="${seq}-${slug}.yaml"

    local filepath="$PENDING_DIR/$filename"

    {
        echo "id: \"${seq}\""
        echo "timestamp: \"${timestamp}\""
        echo "method: ${method}"
        if [ -n "$params_yaml" ]; then
            echo "params:"
            echo "$params_yaml" | sed 's/^/  /'
        else
            echo "params: {}"
        fi
        echo "retryCount: 0"
    } > "$filepath"

    echo "$filepath"
}

# cache_status
# Returns the count of pending items (integer on stdout)
cache_status() {
    _ensure_cache_dirs
    find "$PENDING_DIR" -maxdepth 1 -name '*.yaml' 2>/dev/null | wc -l | tr -d ' '
}

# cache_flush
# Replays all pending commands via repl_invoke in order.
# Outputs summary: flushed=N failed=N pending=N
cache_flush() {
    _ensure_cache_dirs

    # Source repl-invoke if not already loaded
    if ! type repl_invoke >/dev/null 2>&1; then
        source "$CACHE_MANAGER_SCRIPT_DIR/repl-invoke.sh"
    fi

    local flushed=0
    local failed=0

    local items
    items=$(find "$PENDING_DIR" -maxdepth 1 -name '*.yaml' 2>/dev/null | sort)

    if [ -z "$items" ]; then
        echo "flushed=0 failed=0 pending=0"
        return 0
    fi

    while IFS= read -r item; do
        [ -f "$item" ] || continue

        local method
        method=$(grep '^method:' "$item" | sed 's/^method: *//')

        local retry_count
        retry_count=$(grep '^retryCount:' "$item" | sed 's/^retryCount: *//')
        retry_count="${retry_count:-0}"

        # Skip if max retries exceeded
        if [ "$retry_count" -ge "$MAX_RETRIES" ]; then
            continue
        fi

        # Extract params block (between "params:" and "retryCount:")
        local params=""
        params=$(sed -n '/^params:/,/^retryCount:/{ /^params:/d; /^retryCount:/d; s/^  //; p; }' "$item")

        if repl_invoke "$method" "$params" >/dev/null 2>&1; then
            rm -f "$item"
            flushed=$((flushed + 1))
        else
            # Increment retry count
            local new_count=$((retry_count + 1))
            sed -i "s/^retryCount: .*/retryCount: ${new_count}/" "$item"
            failed=$((failed + 1))
        fi
    done <<< "$items"

    echo "flushed=${flushed} failed=${failed} pending=$(cache_status)"
}

export -f cache_write cache_status cache_flush _ensure_cache_dirs 2>/dev/null || true
