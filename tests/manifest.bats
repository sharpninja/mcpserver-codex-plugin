#!/usr/bin/env bats

PLUGIN_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
PLUGIN_MANIFEST="$PLUGIN_ROOT/.codex-plugin/plugin.json"
MARKETPLACE_MANIFEST="$PLUGIN_ROOT/.agents/plugins/marketplace.json"
SKILLS_DIR="$PLUGIN_ROOT/skills"
WORKFLOW_SKILLS=(sync-logs commit-sync wrap-up)

get_frontmatter() {
    local file="$1"
    awk '/^---$/{count++; if(count==2) exit; next} count==1{print}' "$file"
}

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
    for skill in device enforcement graphrag requirements session todo triage workflow workspace sync-logs commit-sync wrap-up; do
        [ -s "$SKILLS_DIR/$skill/SKILL.md" ]
    done
}

@test "workflow skills satisfy AC-SKILLS-001 and AC-SKILLS-002" {
    for skill in "${WORKFLOW_SKILLS[@]}"; do
        local skill_file="$SKILLS_DIR/$skill/SKILL.md"
        [ -s "$skill_file" ]
        get_frontmatter "$skill_file" | grep -Eq "^name:[[:space:]]*.+"
        get_frontmatter "$skill_file" | grep -Eq "^description:[[:space:]]*.+"
    done
}

@test "sync-logs skill documents AC-SKILLS-003" {
    local skill_file="$SKILLS_DIR/sync-logs/SKILL.md"
    grep -Eiq "status check|mcp.*status|Status" "$skill_file"
    grep -Eq "workflow\.sessionlog\.(openSession|beginTurn)|session/turn|turn handling" "$skill_file"
    grep -q "workflow.sessionlog.appendDialog" "$skill_file"
    grep -q "workflow.sessionlog.appendActions" "$skill_file"
    grep -Eiq "background.*session|session.*background" "$skill_file"
    grep -Eiq "factual summary|factual.*summary" "$skill_file"
    grep -Eiq "raw[[:space:]-]*REST" "$skill_file"
}

@test "commit-sync skill documents AC-SKILLS-004" {
    local skill_file="$SKILLS_DIR/commit-sync/SKILL.md"
    grep -Eiq "pause" "$skill_file"
    grep -Eiq "repo-scope|repo scope|dirty tree|dirty-tree" "$skill_file"
    grep -Eiq "acknowledg" "$skill_file"
    grep -Fq "git add -A -- ." "$skill_file"
    grep -Eiq "commit SHA|git rev-parse HEAD" "$skill_file"
    grep -Eiq "push result|git push" "$skill_file"
    grep -Eiq "force|rewrite" "$skill_file"
}

@test "wrap-up skill documents AC-SKILLS-005" {
    local skill_file="$SKILLS_DIR/wrap-up/SKILL.md"
    grep -Eiq "marker trust|trust.*marker" "$skill_file"
    grep -Eiq "requirement reconciliation|requirements.*reconcile|reconcile.*requirements" "$skill_file"
    grep -Eiq "wiki|generateDocument" "$skill_file"
    grep -Eiq "validation" "$skill_file"
    grep -Eiq "commit" "$skill_file"
    grep -Eiq "push" "$skill_file"
    grep -Eiq "session-log reconciliation|session log reconciliation|reconcile.*session" "$skill_file"
    grep -Eq "workflow\.sessionlog\.(completeTurn|failTurn)" "$skill_file"
}

@test "workflow skills are exposed by the Codex plugin manifest for AC-SKILLS-006" {
    grep -q '"skillsPath": "skills"' "$PLUGIN_MANIFEST"
    for skill in "${WORKFLOW_SKILLS[@]}"; do
        [ -s "$SKILLS_DIR/$skill/SKILL.md" ]
    done
}

@test "triage skill documents async incidental bug reporting for TEST-MCP-PLUGIN-TRIAGE-001" {
    local skill_file="$SKILLS_DIR/triage/SKILL.md"
    [ -s "$skill_file" ]
    grep -Eiq "incidental bug" "$skill_file"
    grep -Eiq "active requested fix" "$skill_file"
    grep -Eiq "not expect immediate resolution" "$skill_file"
    grep -Eiq "continue" "$skill_file"
    grep -q "triage_report" "$skill_file"
    grep -q "triage_status" "$skill_file"
    grep -q "workflow.triage.report" "$skill_file"
}

@test "REPL YAML schema exposes workflow.triage methods for TEST-MCP-PLUGIN-TRIAGE-001" {
    local schema_file="$PLUGIN_ROOT/schemas/repl-yaml-message.schema.json"
    [ -s "$schema_file" ]
    grep -Fq 'workflow\\.(sessionlog|todo|memory|requirements|graphrag|triage)' "$schema_file"
    grep -q '"triageRules"' "$schema_file"
    grep -q 'workflow.triage.report' "$schema_file"
    grep -q 'workflow.triage.getReport' "$schema_file"
    grep -q 'workflow.triage.queryGroups' "$schema_file"
    grep -q 'workflow.triage.getGroup' "$schema_file"
    grep -q 'workflow.triage.flushGroup' "$schema_file"
    grep -q 'workflow.triage.retryGroup' "$schema_file"
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
