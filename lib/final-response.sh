#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

response="${1:-}"
if [ -z "$response" ] && [ ! -t 0 ]; then
    response="$(cat 2>/dev/null || true)"
fi

if [ -z "$response" ]; then
    response="Turn completed."
fi

{
    printf 'response: |\n'
    printf '%s\n' "$response" | sed 's/^/  /'
} | "$SCRIPT_DIR/repl-invoke.sh" workflow.sessionlog.completeTurn
