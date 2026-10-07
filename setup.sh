#!/usr/bin/env bash
# setup.sh — Install prerequisites for the McpServer Codex CLI plugin.
# Installs the mcpserver-repl dotnet global tool if not already present.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "QBrain.AI Codex CLI Plugin — Setup"
echo "Script directory: ${SCRIPT_DIR}"

# Install mcpserver-repl if not already on PATH
if command -v qbrain-ai-repl >/dev/null 2>&1 || command -v mcpserver-repl >/dev/null 2>&1; then
    echo "qbrain-ai-repl or mcpserver-repl is already installed."
else
    echo "Installing qbrain-ai-repl or mcpserver-repl..."
    if [ -f "$SCRIPT_DIR/lib/ensure-repl.sh" ]; then
        bash "$SCRIPT_DIR/lib/ensure-repl.sh"
    elif command -v pwsh >/dev/null 2>&1; then
        pwsh -NoLogo -NoProfile -File "$SCRIPT_DIR/lib/ensure-repl.ps1"
    else
        echo "Neither REPL command is installed and pwsh is unavailable." >&2
        exit 1
    fi
fi

echo ""
echo "Setup complete! The QBrain.AI Codex plugin is ready."
echo "Use 'codex --plugin .' from this directory to activate."
