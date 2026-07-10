---
name: Transcript Ingestion
description: Use when Claude, Codex, or Grok needs to import or normalize local JSONL/chat transcript files or folders into MCP Session Log YAML through the shared transcript pipeline.
---

# Transcript Ingestion

Use this skill only from Claude, Codex, and Grok plugin contexts. Cline, Copilot, and OpenCode are supported transcript source formats, not plugin hosts for this iteration.

## Commands

Use the shared PowerShell helper from the plugin `lib` folder:

```powershell
pwsh -NoProfile -NonInteractive -File "$env:MCP_PLUGIN_ROOT/lib/transcript-ingestion.ps1" -Path "<file-or-folder>" -Agent "<Claude|Codex|Grok>" -Source Auto
```

For manual compatibility normalization, pass `-Normalize`. If `-TargetProfile` is omitted, the helper defaults to the invoking plugin profile: Claude maps to Claude, Grok maps to Grok, and all other agents map to Codex. Normalization does not persist unless `-Persist` is also supplied.

```powershell
pwsh -NoProfile -NonInteractive -File "$env:MCP_PLUGIN_ROOT/lib/transcript-ingestion.ps1" -Path "<file-or-folder>" -Agent "Codex" -Normalize -TargetProfile Codex
```

## Behavior

- Ingestion calls `repl.sessionlog.ingestTranscripts` and persists by default.
- Normalization calls `repl.sessionlog.normalizeTranscripts` and does not persist by default.
- The shared server pipeline writes canonical Session Log YAML and optional Claude, Codex, or Grok compatibility JSONL.
- Write-ahead `importRecovery` files remain under `{workspace}/.mcpServer/{agent}/failsafe/pending` unless primary persistence succeeds.
- Checkpoints belong under `{workspace}/.mcpServer/{agent}/transcripts/checkpoints` when a host hook performs incremental recovery.

## YAML Mutation Rule

Never edit YAML by appending, replacing, or removing text lines. Always deserialize the complete document into an object, mutate the object, serialize the object, and save the serialized result. For PowerShell work use `yaml-object-mutation.ps1`; prefer `Set-McpYamlObjectValue` and `Update-McpYamlObject` for durable YAML changes.