#!/usr/bin/env bash
# setup.sh — Install prerequisites for the McpServer Codex CLI plugin.
# Installs the mcpserver-repl dotnet global tool if not already present.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "McpServer Codex CLI Plugin — Setup"
echo "Script directory: ${SCRIPT_DIR}"

# Install mcpserver-repl if not already on PATH
if command -v mcpserver-repl >/dev/null 2>&1; then
    echo "mcpserver-repl is already installed."
else
    echo "Installing mcpserver-repl..."
    bash "$SCRIPT_DIR/lib/ensure-repl.sh"
fi

echo ""
echo "Setup complete! The McpServer Codex plugin is ready."
echo "Use 'codex --plugin .' from this directory to activate."
