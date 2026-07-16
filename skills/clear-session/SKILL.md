---
name: Clear Session
description: Use when the user asks to "clear session", "reset session", "clear-session", or wants to end the current MCP session, clear agent context, reload the agent instruction file, reload the operator profile, and return to a fresh ready state.
version: 0.1.0
---

# Clear Session

## Overview

Reset the agent to a clean, ready state in five ordered steps: end the current MCP session, clear agent context, reload the agent instruction file, run the add-profile skill, then report ready. Run this when the user asks to "clear session" / "reset session" / invokes `/clear-session`.

Do not skip a step. Each step must complete, or be explicitly reported as host-limited, before moving to the next. Use only supported plugin wrappers for session and cache operations (`lib/repl-invoke.ps1`, `Invoke-McpPlugin.ps1`, and the `hooks/scripts/*.ps1` where your host installs them); never raw REST and never hand-edit session-log or cache files.

`workflow.*` names in this skill are plugin workflow/REPL method names, not literal native MCP tool names. Native McpServer `/mcp-transport` discovery uses names such as `sessionlog_*`; do not call the plugin unavailable solely because `workflow.*` names are absent from generic MCP discovery.

## Step 1 - End the current MCP session

Close out the active session-log turn and session through the plugin wrapper:

1. If a turn is open, finalize it with `workflow.sessionlog.completeTurn` (or `workflow.sessionlog.failTurn` if the work was blocked). Drive it through the wrapper:

   ```pwsh
   pwsh -NoProfile -File "<plugin-root>/lib/repl-invoke.ps1" -Method workflow.sessionlog.completeTurn -ParamsYaml @'
   response: Clearing session and resetting to a ready state.
   '@
   ```

   The equivalent function form is `Invoke-McpPlugin.ps1 "workflow.sessionlog.completeTurn" "<yaml params>"`.

2. Run the session-end path so the local `session-state.yaml` and `current-turn.yaml` are closed. Where your host installs hook scripts, use:

   ```pwsh
   pwsh -NoProfile -File "<plugin-root>/hooks/scripts/session-end.ps1"
   ```

   If your host has no `hooks/scripts/session-end.ps1`, drive the session-end through the wrapper instead.

Confirm no `in_progress` turn remains before continuing.

## Step 2 - Clear agent context (best-effort auto, else instruct)

First clear the plugin's local session/working state programmatically. Where your host installs it, run the cache-flush hook:

```pwsh
pwsh -NoProfile -File "<plugin-root>/hooks/scripts/cache-flush.ps1"
```

If your host has no `hooks/scripts/cache-flush.ps1`, clear the local `current-turn.yaml` / `session-state.yaml` through the wrapper so the next session starts clean.

Then clear the host conversation context on a best-effort basis: if your host exposes a programmatic clear (a tool, command, or hook the plugin can invoke), invoke it. Otherwise print the host's manual clear command for the user and STOP; wait for the user to confirm the context is cleared before continuing.

Per-host manual clear command (select by `MCP_PLUGIN_HOST` / your agent identity):

- claude-code, claude-cowork (Claude): `/clear`
- codex (Codex): `/new`
- copilot (Copilot): start a new chat / clear the conversation
- grok (Grok): `/clear` (or start a new session)
- cline, cline-v2 (Cline): start a New Task
- opencode (OpenCode): `/new` (or `/clear`)

Most hosts clear conversation context only on a user action, so the honest default is to print the exact command above for the detected host and pause for confirmation. Do not claim context was cleared when only the user can perform the clear.

## Step 3 - Load the agent instruction file

Re-read the marker and the agent instruction file fresh, and treat them as the authoritative source for subsequent turns:

1. Always read `AGENTS-README-FIRST.yaml` first (marker: endpoints, API key, trust rules). Verify marker trust before any state-changing MCP call.
2. Read the agent instruction file for the detected host:
   - claude-code, claude-cowork: `CLAUDE.md` (and `AGENTS.md` if present)
   - codex, copilot, grok, cline, cline-v2, opencode: `AGENTS.md`
   Fall back to `AGENTS.md` when the host-specific file is absent, and also read a workspace-level `CLAUDE.md` / `AGENTS.md` when present.

Do not compact, summarize, or paraphrase these files; carry their instructions verbatim.

## Step 4 - Run add-profile

Execute the add-profile skill (`/add-profile`) to reload the operator profile and standing instructions. If add-profile is not available for this host, read the operator profile source it would load and apply it. Re-run add-profile after any later model change or effort-level change.

## Step 5 - Report ready

Report a concise readiness summary that states only what actually happened:

- MCP session: ended (turn finalized, session closed, no `in_progress` turn).
- Context: cleared (auto) OR awaiting user clear command (host-limited): state which.
- Instruction file: reloaded (name the file: `CLAUDE.md` or `AGENTS.md`).
- Profile: reloaded via add-profile.
- Ready for the next request.

If Step 2 required a user action that has not been confirmed, report "awaiting context clear" instead of "ready". Report ready only when every prior step actually completed.
