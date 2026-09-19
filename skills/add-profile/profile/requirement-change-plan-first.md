---
name: requirement-change-plan-first
description: "feedback - if Payton changes or adds a requirement, write a BDPv4 plan first and wait for explicit approval before implementing"
metadata:
  type: feedback
  origin: operator-directive-2026-08-15
---

# Requirement change or add: plan first, then approval, then implement

**Locked 2026-08-15 by operator.** Verbatim intent: if he changes or adds a requirement, first create a plan using Byrd Development Process v4, then implement that plan only after his approval.

## What this applies to

Any operator request that creates or changes a project requirement. That includes a new FR/TR/TEST, a change to an existing FR/TR/TEST or its acceptance criteria, and a product behavior change that is a requirement change rather than a bug in already-specified behavior.

## Required order

1. Capture or update the requirement through MCP (FR/TR/TEST/AC). Do not start product implementation in the same breath.
2. Write a decision-complete BDPv4 plan: requirements drive tests, tests first (shown red), mocks/stubs where required, implement only after tests are correct, full suite green to exit a phase, hostile review at each phase gate.
3. Stop. Present the plan. Wait for explicit approval (for example "Yes, I approve the change").
4. Only then implement, following the approved plan and its gates.

## What this is not

This does not cancel the 2026-07-13 bug-report amendment. A bug in already-specified behavior is still pre-approved: diagnose, state the plan, execute via Byrd immediately. See [[approve-before-execute]].

A requirement add or change is not a bug report. Do not treat "the product should now do X" as pre-approved implementation.

## How to apply

- Do not write or keep writing product implementation for an unapproved requirement change.
- Do not mark the related PLAN TODO done on the strength of unapproved mid-stream code.
- If code was already written before this rule was stated, say so plainly, leave or revert only as the operator directs, and still present the BDPv4 plan for approval before any further implementation or done claim.

Links: [[approve-before-execute]], [[hostile-phase-gates]], [[accuracy-first-verify-sources]].
