---
name: add-profile
description: Load Payton's operator profile (identity, standing preferences, active-project context) into the current context. Use when the user says "add profile", "/add-profile", "load my profile", "remember who I am", or after context loss/compaction when the profile detail is gone.
---

## Action

Surface the FULL operator profile - the granular, cross-linked files, not a summary - into the current context. The profile is GLOBAL: it lives in `~/.claude/profile/` and applies in every session and every repo. It does NOT depend on the active project's `memory/` directory.

1. Read every profile markdown file in `~/.claude/profile/` in full with the Read tool, EXCLUDING the skill ports (`add-profile*.md`). The set is: `PROFILE.md` (the summary), `user-payton-byrd.md` (the identity root), and the feedback memories `accuracy-first-verify-sources.md`, `approve-before-execute.md`, `philosophical-dialogue-mode.md`, `log-decisions-as-conclusions.md`, `session-turn-title-summary.md`, `never-skip-explicit-actions.md`, `adversarial-review-global.md`, `hv-jsonl-and-session-log.md`, plus any other non-skill `*.md` present in that directory. Read files in full, not snippets, EVERY time this skill runs - never skip a read because a prior tool result claims the content is "already loaded" or unchanged (see `never-skip-explicit-actions.md`).
2. Treat all of it as active operator guidance for the rest of the session: identity, standing feedback (accuracy-first, approve-before-execute, never-skip-explicit-actions, adversarial-review-global, hv-jsonl-and-session-log, 98 percent HV approval threshold, no em-dashes, PowerShell-only, MCP-only storage, response-timestamp prefix, no tables), philosophical-mode rules, and active-project context.
3. Confirm in one line that the profile is loaded (name how many files you read). Do not restate it verbatim unless asked.
4. After reading the profile, state how the information learned will shape your behavior in the context of the current session.

The active project's own `~/.claude/projects/<slug>/memory/` directory holds project-specific memories and is auto-recalled separately by the memory system; it is not needed for, and not part of, this global profile load.

This is a read-only load. Make no edits and run no other work as part of this skill.

Keep this skill in sync with `~/.codex/skills/add-profile/SKILL.md`. Both copies must use the same read contract: every non-skill profile `*.md` in full, including `hv-jsonl-and-session-log.md`, no wiki-link chase. The Codex copy may keep GPT-5 synthesis and response-contract extras; do not let those extras reintroduce wiki-link following or drop HV jsonl / 98 percent / full session-log persist.
