---
name: Device Validation
description: This skill should be used for attached Android validation workflows that can be driven through adb_step.
---
## Goal

Allow Codex to perform mechanical Android device interaction through `adb_step` instead of requiring manual user testing whenever feasible.

## Default Loop

1. Capture a screenshot with `adb_step`.
2. Inspect the visible UI state.
3. Perform the next mechanical action with `adb_step`.
4. Capture another screenshot.
5. Decide whether the task is complete, requires another device action, or needs code changes.
6. Record progress or failure in session log.

## Supported Action Types

Use `adb_step` for:
- screenshot
- tap
- swipe
- text
- keyevent
- wait
- launch_app
- get_focus

This skill provides workflow guidance only. It does not add a new MCP tool or wrapper implementation.

## Rules

- Use `adb_step` for mechanical actions only.
- Keep reasoning and navigation decisions in Codex.
- Prefer screenshot -> inspect -> act -> screenshot loops.
- Ask the user for help only when:
  - no device is connected
  - multiple devices are connected and the correct device is unknown
  - credentials or destructive confirmation are required
  - the visible UI is ambiguous or blocked

## Anti-Patterns

Avoid:
- asking the user to test manually before attempting `adb_step`
- modifying source code when the task only needs device validation
- assuming device state without a screenshot or explicit focus check
