---
name: no-python-lab
description: "feedback - standing lab rule: never use Python; pwsh.exe only for automation"
metadata:
  node_type: memory
  type: feedback
  originSessionId: GrokCode-20260722T114935Z-plugin-session
---

Standing lab rule (Payton, 2026-07-22, locked, verbatim intent): **"You may not use Python. That is a standing rule in my lab."**

**Why:** Python is forbidden on lab machines for agent automation. PowerShell is the only approved shell scripting path.

**How to apply:** Do not invoke `python`, `python3`, `py`, or Python one-liners for scripts, parsing, JSON/YAML construction, freezes, verification, scraping, or analysis. Use `pwsh.exe -NoProfile -NonInteractive` for shell work. Prefer native objects + `ConvertTo-Json` / `ConvertFrom-Json` / project helpers. .NET, Node only when the project already requires it for a non-agent path (never for JSON/YAML payload construction per existing lab rules). Applies on PAYTON-DESKTOP and PAYTON-LEGION2 and every workspace. Links: [[user-payton-byrd]], [[accuracy-first-verify-sources]], [[never-skip-explicit-actions]].
