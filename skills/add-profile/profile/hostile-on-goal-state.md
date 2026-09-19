---
name: hostile-on-goal-state
description: "feedback - hostile AGREE is required before any goal or TODO state change to done"
metadata:
  type: feedback
  origin: operator-directive-2026-08-16
---

# Hostile validation on goal state changes

**Locked 2026-08-16 by operator.** Verbatim intent: add hostile validation to goal state changes. Do not mark a goal, plan step, or MCP TODO `done: true` when there is an outstanding failure.

## What this applies to

Any state change that claims a goal is complete: MCP TODO `done: true`, FR/TR/TEST `status: completed` with `isSatisfied: true`, plan-step `[x]`, or a chat claim of done/green/complete for a tracked plan.

## Required order

1. Full applicable suite green (Failed 0, Skipped 0) for the exit gate. A red Phase 1 is not an exit.
2. Independent hostile review of the done claim. OverallVerdict AGREE, with accuracy and completeness both at least 98 percent. Cite request jsonl, response jsonl, and the HV session-log turn that holds the entire verdict body. See [[hv-jsonl-and-session-log]] and [[adversarial-review-global]].
3. Only then change the goal state. Cite those HV receipt paths in `doneSummary`.

## Forbidden

- Marking `done: true` while any required test is failing, hanging, or unrun.
- Marking a combined plan done while a later slice is still open.
- Treating a focused-filter green as enough when the plan requires the full unit suite.
- Self-check as a substitute for hostile AGREE.
- Treating HV as complete without request jsonl, response jsonl, and the full verdict in the MCP session log.
- Accepting AGREE when accuracy or completeness is below 98 percent.

Links: [[adversarial-review-global]], [[hostile-phase-gates]], [[approve-before-execute]].
