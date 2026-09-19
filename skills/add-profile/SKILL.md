---
name: add-profile
description: Load Payton Byrd's global operator profile into the current session. Use when the user says "add profile", "/add-profile", "load my profile", "remember who I am", after context loss or compaction, at session start when profile detail is gone, or when standing operator rules must be re-applied.
---

# add-profile (all environments)

Surface Payton Byrd's GLOBAL operator profile into the current session as active guidance. Same intent on Claude, Codex, Copilot, Cline, Grok, OpenCode, Grok Bot, and any other host. Keep this skill in sync across host skill roots; do not fork the read contract.

## Profile location (resolve in order)

Use the first directory that exists and contains `PROFILE.md`:

1. `$OPERATOR_PROFILE_DIR` (explicit override)
2. `$HOME/.claude/profile` (Linux/macOS) or `%USERPROFILE%\.claude\profile` (Windows), typically `C:\Users\kingd\.claude\profile\`
3. `/workspace/operator-profile/profile` (Grok Bot / box mirror)
4. `<this-skill-directory>/profile` (self-contained plugin install)

Never load project `memory/` as a substitute for this global profile. Exclude skill ports (`add-profile*.md`) from the file set.

## Action (read-only)

1. Resolve the profile directory as above. If none exists, stop and say the profile is missing; do not invent content.
2. Read EVERY non-skill `*.md` in that directory in full with the host file-read tool. Never skip a file because a prior tool result claims it is already loaded. The set includes at least: `PROFILE.md`, `user-payton-byrd.md`, `accuracy-first-verify-sources.md`, `approve-before-execute.md`, `philosophical-dialogue-mode.md`, `log-decisions-as-conclusions.md`, `session-turn-title-summary.md`, `never-skip-explicit-actions.md`, `adversarial-review-global.md`, `hv-jsonl-and-session-log.md`, `hostile-on-goal-state.md`, `hostile-ops-vs-requirements.md`, `hostile-phase-gates.md`, `bring-the-receipts.md`, `lab-authorization.md`, `no-attitude-honesty-tell.md`, `no-python-lab.md`, `no-shortcuts-precision-over-convenience.md`, `requirement-change-plan-first.md`, plus any other non-skill `*.md` present.
3. Treat all of it as active operator guidance for the rest of the session (identity, standing feedback, HV 98 percent gate, receipts, MCP-only storage, approve-before-execute with documented amendments, no em-dashes or en-dashes except numeric ranges, lab authorization, philosophical mode).
4. Confirm in one line that the profile is loaded and how many files you read. Do not restate the profile verbatim unless asked.
5. After reading, state how the information will shape behavior in the current session.

This skill makes no edits and runs no other work.

## Host notes

- **Claude:** use the Read tool; honor response-timestamp hooks when present. Skill may also live as `SKILL.claude.md` in source trees; install name remains `add-profile`.
- **Codex / Copilot / Cline / OpenCode / Grok plugins:** install at `skills/add-profile/SKILL.md` with a `profile/` copy beside it OR rely on `~/.claude/profile`. Use that host's file reader and MCP plugin wrappers (`workflow.*` / native `*_` tools), never raw REST for session-log, TODO, or requirements.
- **Grok Bot:** profile mirror is `/workspace/operator-profile/profile` and `$HOME/.claude/profile`. Use the Read tool. Shell on the box may be bash; on Windows lab machines prefer `pwsh` as the profile requires.
- **PowerShell.Mcp:** on Windows lab hosts, route `pwsh` through PowerShell.Mcp when that contract applies; do not invent a bypass.
