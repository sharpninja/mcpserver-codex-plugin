---
name: hostile-ops-vs-requirements
description: "feedback - hostile validation must not demand FR/TR/TEST for user-directed operational actions; only for project requirement work"
metadata:
  type: feedback
  origin: operator-directive-2026-08-14
---

# Hostile review: project work vs operator actions

**Locked 2026-08-14 by operator.** Verbatim intent: uninstalling an obsolete package (or any similar user-directed lab action) is **not** project requirements work. Hostile Validation must differentiate.

## Two work classes

1. **Project implementation scope**: product code, product tests, project documentation, and plan-step completion for that implementation. **Byrd v4 and related directives pertain only to this class.** Missing FR/TR/TEST/AC for claimed-complete implementation work is FAIL on surface C.

2. **User-directed general actions**: operator-ordered lab/ops work that is not a product requirement. Examples: uninstall an obsolete package, back up a device, pair wireless ADB, take a screenshot, copy a store the operator named, remove a leftover launcher. These are not FR/TR/TEST. Surface C must **not** FAIL for "no FR/TR for this uninstall" or equivalent.

## How hostile must classify

- Classify the request first. Record the class on the receipt.
- If the operator explicitly directed the action, default to class 2 unless the implementer also shipped product code or claimed a plan/FR complete.
- Do not invent a requirements gap to punish class-2 work.
- If class-2 work is mixed with class-1 product changes in the same turn, score them separately. FAIL C only on the class-1 slice.

## What still applies to class-2 work

- Surface A: did they do the directed action, with receipts.
- Surface B: honesty, receipts, look-before-delete, PowerShell/no-Python, MCP-only storage. Not Byrd TDD for the ops action itself.
- Surface D: only if they claim an active plan step is complete. An ops action does not have to satisfy an unrelated product plan DoD.

Links: [[adversarial-review-global]], hostile-validator skill.
