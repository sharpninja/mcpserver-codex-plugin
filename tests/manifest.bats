#!/usr/bin/env bats

PLUGIN_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
PLUGIN_MANIFEST="$PLUGIN_ROOT/.codex-plugin/plugin.json"
MARKETPLACE_MANIFEST="$PLUGIN_ROOT/.agents/plugins/marketplace.json"

assert_json_contract() {
    if command -v node >/dev/null 2>&1 && node --version >/dev/null 2>&1; then
        node - "$PLUGIN_ROOT" <<'JS'
const fs = require("fs");
const path = require("path");

const root = process.argv[2];
const plugin = JSON.parse(fs.readFileSync(path.join(root, ".codex-plugin", "plugin.json"), "utf8"));
const marketplace = JSON.parse(fs.readFileSync(path.join(root, ".agents", "plugins", "marketplace.json"), "utf8"));

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

assert(plugin.name === "mcpserver", "plugin name");
assert(/^\d+\.\d+\.\d+$/.test(plugin.version), "plugin version must be semver");
assert(plugin.description.includes("OpenAI Codex CLI"), "plugin description");
assert(plugin.author.name === "Payton Byrd (The Sharp Ninja)", "plugin author name");
assert(plugin.author.developerName === "sharpninja", "plugin developerName");
assert(plugin.homepage === "https://github.com/sharpninja/McpServer", "plugin homepage");
assert(plugin.repository === "https://github.com/sharpninja/mcpserver-codex-plugin", "plugin repository");
assert(plugin.license === "MIT", "plugin license");
assert(plugin.skillsPath === "skills", "plugin skillsPath");
for (const keyword of ["mcp", "todo", "session-log", "requirements", "graphrag"]) {
  assert(plugin.keywords.includes(keyword), `missing plugin keyword ${keyword}`);
}

assert(marketplace.name === "mcpserver-codex-plugin", "marketplace name");
assert(marketplace.interface.displayName === "McpServer Codex Plugin", "marketplace displayName");
assert(Array.isArray(marketplace.plugins) && marketplace.plugins.length === 1, "marketplace plugin count");
const entry = marketplace.plugins[0];
assert(entry.name === "mcpserver", "marketplace plugin name");
assert(entry.source.source === "local", "marketplace source type");
assert(entry.source.path === ".", "marketplace source path");
assert(entry.policy.installation === "AVAILABLE", "marketplace installation policy");
assert(entry.policy.authentication === "ON_INSTALL", "marketplace authentication policy");
assert(entry.category === "Engineering", "marketplace category");
JS
    elif command -v py >/dev/null 2>&1 && py -3 --version >/dev/null 2>&1; then
        py -3 - "$PLUGIN_ROOT" <<'PY'
import json
import os
import re
import sys

root = sys.argv[1]
with open(os.path.join(root, ".codex-plugin", "plugin.json"), encoding="utf-8") as handle:
    plugin = json.load(handle)
with open(os.path.join(root, ".agents", "plugins", "marketplace.json"), encoding="utf-8") as handle:
    marketplace = json.load(handle)

assert plugin["name"] == "mcpserver"
assert re.fullmatch(r"\d+\.\d+\.\d+", plugin["version"])
assert "OpenAI Codex CLI" in plugin["description"]
assert plugin["author"]["name"] == "Payton Byrd (The Sharp Ninja)"
assert plugin["author"]["developerName"] == "sharpninja"
assert plugin["homepage"] == "https://github.com/sharpninja/McpServer"
assert plugin["repository"] == "https://github.com/sharpninja/mcpserver-codex-plugin"
assert plugin["license"] == "MIT"
assert plugin["skillsPath"] == "skills"
for keyword in ("mcp", "todo", "session-log", "requirements", "graphrag"):
    assert keyword in plugin["keywords"], keyword

assert marketplace["name"] == "mcpserver-codex-plugin"
assert marketplace["interface"]["displayName"] == "McpServer Codex Plugin"
assert len(marketplace["plugins"]) == 1
entry = marketplace["plugins"][0]
assert entry["name"] == "mcpserver"
assert entry["source"]["source"] == "local"
assert entry["source"]["path"] == "."
assert entry["policy"]["installation"] == "AVAILABLE"
assert entry["policy"]["authentication"] == "ON_INSTALL"
assert entry["category"] == "Engineering"
PY
    else
        skip "No JSON parser available for manifest validation"
    fi
}

@test "plugin and marketplace manifests use the Codex plugin contract" {
    [ -s "$PLUGIN_MANIFEST" ]
    [ -s "$MARKETPLACE_MANIFEST" ]

    assert_json_contract
}

@test "manifest skillsPath points to every expected skill entrypoint" {
    for skill in device enforcement graphrag requirements session todo workflow workspace; do
        [ -s "$PLUGIN_ROOT/skills/$skill/SKILL.md" ]
    done
}

@test "hook and support scripts exist with bash shebangs" {
    for script in \
        setup.sh \
        lib/cache-manager.sh \
        lib/cache-scope.sh \
        lib/code-verify.sh \
        lib/ensure-repl.sh \
        lib/final-response.sh \
        lib/marker-resolver.sh \
        lib/mcp.codex.status.sh \
        lib/repl-invoke.sh \
        lib/session-start.sh \
        lib/stop-gate.sh \
        lib/user-prompt-submit.sh
    do
        [ -s "$PLUGIN_ROOT/$script" ]
        read -r first_line < "$PLUGIN_ROOT/$script"
        [ "$first_line" = "#!/usr/bin/env bash" ]
    done

    [ -s "$PLUGIN_ROOT/Invoke-CodexMcpPlugin.ps1" ]
}

@test "mutable cache state is ignored and not shipped as tracked content" {
    for ignored_path in \
        "cache/pending/*.yaml" \
        "cache/session-state.yaml" \
        "cache/internal-todo.yaml" \
        "cache/plan-todo-map.yaml" \
        "cache/current-turn.yaml" \
        "cache/todo-state.yaml" \
        "cache/workspaces/"
    do
        grep -Fxq "$ignored_path" "$PLUGIN_ROOT/.gitignore"
    done

    run git -C "$PLUGIN_ROOT" ls-files \
        "cache/session-state.yaml" \
        "cache/internal-todo.yaml" \
        "cache/plan-todo-map.yaml" \
        "cache/current-turn.yaml" \
        "cache/todo-state.yaml" \
        "cache/workspaces/*" \
        "cache/pending/*.yaml"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}
