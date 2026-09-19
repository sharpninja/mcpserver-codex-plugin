---
name: hostile-phase-gates
description: "feedback - Byrd phase-order (requirements drive tests) is caught by hostile review between plan implementation phases, not post-hoc file timestamps"
metadata:
  type: feedback
  origin: operator-directive-2026-08-14
---

# Hostile reviews between Byrd phases

**Locked 2026-08-14 by operator.** Verbatim intent: a FAIL that "requirements did not drive tests" because FR `createdAt` is later than the test file should have been caught by a hostile review **between phases of plan implementation**.

## Parent duty

For project implementation, run hostile validation at each Byrd phase gate before starting the next phase:

1. After FR/TR/TEST/AC exist
2. After AC-covering tests are written (red)
3. After implementation (green)
4. Before claiming done/deploy. Hostile OverallVerdict AGREE is required before any goal, plan step, or MCP TODO `done: true`. Do not mark done when a required test is failing. See [[hostile-on-goal-state]].

## Late-review rule

A review after the slice is already on disk:

- May FAIL a **claimed** phase complete that has no inter-phase hostile AGREE
- Must **not** FAIL B2 solely by comparing FR `createdAt` to test or implementation `LastWriteTime`

Links: [[adversarial-review-global]], [[hostile-on-goal-state]], hostile-validator skill.
