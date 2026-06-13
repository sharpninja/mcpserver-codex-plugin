#!/usr/bin/env bash
# code-verify.sh - generated McpServer plugin hook wrapper (codex).
# Generated from plugins/core/hooks-templates; do not edit in the plugin repo.
# All logic lives in lib/hook-lib.sh; host knobs live in lib/plugin-env.sh.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/../lib/plugin-env.sh"
. "$SCRIPT_DIR/../lib/hook-lib.sh"
hook_env_init scoped
code_verify_main "$@"
