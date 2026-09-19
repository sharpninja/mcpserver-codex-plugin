---
name: hv-jsonl-and-session-log
description: "feedback - HV request and response must be jsonl files; HV results must be saved in full to the MCP session log; 98 percent is the minimum approval threshold"
metadata:
  type: feedback
  origin: operator-directive-2026-09-10
---

# Hostile validation receipts (locked 2026-09-10)

**Operator directive, 2026-09-10.** Applies to every hostile validation (HV) from now on: Codex extra-high HV, Grok `hostile-validator`, and any other independent adversarial reviewer. Global. Not optional.

## 1. Request and response jsonl (mandatory)

Every HV launch must persist **two jsonl files** before the review is treated as complete:

1. **Request jsonl.** One JSON object per line covering the HV ask as sent: UTC stamp, workspace path, reviewer identity (agent, model, effort), launch command, prompt/body, named evidence paths, and the gate or TODO under review.
2. **Response jsonl.** The reviewer's full machine stream as jsonl. For Codex CLI that is the `--json` event stream (every `thread.started`, tool, `agent_message`, and `turn.completed` line). For a Grok hostile sub-agent, write one object per reviewer message/tool result, then a final object with the complete verdict.

Do not keep these only in `%TEMP%` or a wiped scratch tree. Durable locations, in order:

- Git workspace: `docs/receipts/hv/{utc}-{gate}.request.jsonl` and `docs/receipts/hv/{utc}-{gate}.response.jsonl`
- Otherwise: `%USERPROFILE%\.grok\hv-receipts\{workspace-slug}\{utc}-{gate}.request.jsonl` and the matching `.response.jsonl`

A missing request jsonl, a missing response jsonl, or a response file that is only a one-line summary is an incomplete HV. Incomplete HV cannot AGREE and cannot authorize done.

Build jsonl from native objects and serialize. PowerShell only. No Python. No handwritten JSON.

## 2. Ninety-eight percent minimum approval threshold

A hostile validation passes only when **both** its accuracy score and completeness score are **at least 98 percent**. Any individual score below 98 is a failure. `OverallVerdict` must be `DISAGREE` when either score is below 98, even if claim FAIL and UNKNOWN counts are both zero.

If the reviewer emits AGREE/DISAGREE without numeric accuracy and completeness scores, the HV is incomplete: treat as DISAGREE until scores are present and at least 98.

This is an acceptance threshold, not a target to inflate. It supersedes any earlier practice that accepted AGREE with a lower score. It applies to in-flight and future HV.

A sub-98 score cannot authorize a goal, TODO, requirement, or plan done-state change. Display the sub-98 score as a failure, remediate, and rerun HV.

See [[adversarial-review-global]] (score gate locked 2026-09-10).

## 3. Entire HV result in the MCP session log

The results of HV validation must be saved **in their entirety** to the MCP Session Log. A one-line "AGREE" or a paraphrase is not the result.

The reviewer's session-log turn (plugin `workflow.sessionlog.*` / native `sessionlog_*`; never hand-edit log files) must include:

- The complete verdict prose, every finding, every PASS/FAIL/UNKNOWN item, scores, OverallVerdict, thread/session/request ids
- The complete `=== VERDICT JSON ===` object (or equivalent structured verdict)
- Absolute paths to the request jsonl and response jsonl
- Proof the session-log turn persisted (`queryHistory` or equivalent)

If a field is too large for one session-log write, split across ordered dialog/action items on the **same** turn until the full verdict body is stored. Do not omit findings to fit. The jsonl files remain the byte-complete stream; the session log must still carry the full verdict text, not a digest.

A review without this full session-log persist is incomplete even if jsonl files exist.

## Forbidden

- HV with no request jsonl or no response jsonl
- HV whose only record is Temp/scratch that can be wiped
- AGREE without accuracy and completeness both at or above 98
- Summarizing HV into the session log instead of storing the entire result
- Marking a goal/TODO/plan done on incomplete HV

Links: [[adversarial-review-global]], [[hostile-on-goal-state]], [[bring-the-receipts]], [[never-skip-explicit-actions]].
