---
name: adversarial-review-global
description: "feedback - global directive: every result adversarially reviewed, timestamped, failures displayed, accuracy+completeness ratings; adversarial reviewers must write complete MCP session-log turns; deploy via Nuke never manual"
metadata:
  type: feedback
  origin: operator-directive-2026-08-12
---

# Adversarial review and deploy (global, permanent)

**Locked 2026-08-12 by operator.** Applies in every session and every repo. Not optional. Not McpServer-only.

## Every result of every request

1. **Adversarial validation.** Independently validate via a hostile reviewer sub-agent (`hostile-validator` skill / `spawn_subagent`). Self-check alone is not validation.
2. **UTC timestamp.** Every result is timestamped in UTC.
3. **Display review failures.** Every FAIL and UNKNOWN from the adversarial review is shown to the user. Never bury failures.
4. **Accuracy and completeness ratings.** Every result includes both an **accuracy** rating and a **completeness** rating (numeric scale with short justification).

## Hostile validation score gate (locked 2026-09-10)

**Effective immediately:** a hostile validation passes only when both its accuracy score and completeness score are at least 98 percent. Any individual score below 98 percent is a failure. `OverallVerdict` must be `DISAGREE` when either score is below 98, even if the claim FAIL and UNKNOWN counts are both zero.

A result with either score below 98 cannot authorize a goal, TODO, requirement, or plan done-state change. The parent must display every sub-98 score as a failure, remediate the deficiency, and rerun hostile validation before acceptance.

This applies to the current in-flight review and all future hostile reviews. It supersedes any earlier practice that accepted an `AGREE` verdict with a lower numeric score. The 98 percent rule is an acceptance threshold, not a target reviewers may game or inflate.

## Hostile validation mandatory scope (locked 2026-08-13)

**Operator directive (verbatim intent):** Hostile Validation must test for **workspace rule violations**, **requirement violations**, and the **current plan holistically**, **in addition to** the requested validation.

Applies every hostile run, every workspace. Not optional. Not limited to McpServer use-case UI checks.

Mandatory attack surfaces on every run:

1. **Requested validation** — every implementer claim (pass/done/green/fixed, SHAs, test counts, receipts).
2. **Workspace rules** — honesty, receipts, MCP-only TODO/session/requirements storage when the workspace uses MCP, lab PowerShell/no-Python. **Byrd Development Process v4 and related directives pertain only to code and documentation in the scope of implementing the project.** Phase-order (requirements drive tests; tests before implementation) is caught by a hostile review **between phases** of plan implementation. Do not FAIL B2 solely by comparing FR `createdAt` to test/implementation file times after the slice is written. Do not apply Byrd TDD to user-directed ops.
3. **Requirements** — apply to **project requirement work** only (product features, implementation, claimed-complete plan steps). FR/TR/TEST/AC/mappings required there. Missing FR/TR/AC for claimed-complete implementation work is FAIL.
   **Do not apply surface C to user-directed general actions** (uninstall an obsolete package, device backup, ADB pair, screenshot, operator-named restore/copy). Those are not project requirements. "No FR/TR for this uninstall" is not a valid FAIL. Classify the work on the receipt. If a turn mixes ops and product work, FAIL C only on the product slice. See `hostile-ops-vs-requirements.md`.
4. **Current plan holistically** — when the implementer claims plan-step completion: plan DoD, blockers, amendments, exit criteria. A user-directed ops action does not have to satisfy an unrelated product plan DoD unless they claimed that plan step done.

**OverallVerdict=AGREE** only if all *applicable* surfaces of (1)+(2)+(3)+(4) PASS. Surface C is N/A (not a FAIL) for class-2 operator actions. Parent agents must not under-scope the brief to code-only claims on class-1 work; if they do, the hostile sub-agent expands and still evaluates applicable (2)+(3)+(4).

**add-profile first:** Hostile validator must execute the `add-profile` skill before beginning its validation work (every run, including resume). Receipt must record that it ran.

Authoritative skill text: `~/.grok/skills/hostile-validator/SKILL.md`.

## Adversarial reviewer session-log obligation

**All adversarial reviewers must create complete MCP Session Log turns for every review performed.**

Required lifecycle (plugin `workflow.sessionlog.*` / equivalent, never hand-edit log files):

1. bootstrap (if needed)
2. openSession (dedicated review session or clear review turn on agent session)
3. beginTurn
4. appendDialog / appendActions (integer `order` values)
5. completeTurn or failTurn
6. Prove persistence (`queryHistory` or equivalent server proof in the hostile receipt)

A review without a complete session-log turn is **incomplete**, even if claim verdicts would otherwise pass.

## HV jsonl and full session-log body (locked 2026-09-10)

**Operator directive (verbatim intent):** HV requests must have request and response logged as jsonl files from now on. The results of HV validation must be saved in their entirety to the MCP Session Log.

Every HV launch writes two durable jsonl files (request as sent; response as the full `--json` or equivalent stream). Do not leave them only in Temp/scratch. Workspace path: `docs/receipts/hv/{utc}-{gate}.request.jsonl` and `.response.jsonl`; otherwise `%USERPROFILE%\.grok\hv-receipts\`.

The reviewer's MCP session-log turn must store the **entire** HV result: full verdict prose, every finding, scores, OverallVerdict, VERDICT JSON, and jsonl paths. A one-line AGREE or a paraphrase is not the result. Missing jsonl or a summarized session-log body makes the HV incomplete; incomplete HV cannot AGREE and cannot authorize done.

See [[hv-jsonl-and-session-log]].

## Status report contract after validation

Parent status reports that claim pass/done/green/complete must include:

- Receipt path
- `OverallVerdict` (`AGREE` or `DISAGREE`)
- PASS / FAIL / UNKNOWN counts
- Full FAIL list
- Adversarial sessionId + turn requestId when session-log was required

If the receipt is missing or `OverallVerdict` is `DISAGREE`, **do not** claim step completion and **do not** change a goal, plan step, or MCP TODO to `done: true`. Hostile AGREE is required before any goal-state change. See `hostile-on-goal-state.md`.

## Deploy: Nuke only, never manual

When deploying McpServer (and other lab services that ship with Nuke targets):

- **Use Nuke** (for McpServer: elevated `./build.ps1 UpdateService` as documented on the target).
- **Never** hand-copy binaries into `C:\ProgramData\...`, never ad-hoc `Stop-Service`/`Start-Service` + `Copy-Item` deploy scripts as a substitute for Nuke.
- Manual file edits of live config may be acceptable when they are the intended change (e.g. `appsettings.yaml` provider flags) and Nuke restore/preserve rules keep them; binary deploy still goes through Nuke.

## Related standing feedback

- [[accuracy-first-verify-sources]]
- [[bring-the-receipts]]
- [[never-skip-explicit-actions]]
- [[lab-authorization]]
- [[hostile-on-goal-state]]
- [[hv-jsonl-and-session-log]]

## Hostile validator skill note

`hostile-validator` skill text is the operational brief (including mandatory surfaces A–D). **This profile file is the broader permanent rule:** every result, every request, every workspace. Code-only hostile briefs that omit Byrd/requirements/plan are non-compliant.
