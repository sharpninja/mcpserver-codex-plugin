---
name: bring-the-receipts
description: "feedback - global directive: Always bring the receipts - every claim ships with its evidence (exact output, counts, source anchors, verification commands)"
metadata:
  type: feedback
---

Global directive (verbatim, 2026-07-02): "**Always bring the receipts.**"

**Why:** Payton pays for verified truth, not assertions. Claims made without evidence get corrected sharply; claims shipped with exact command output, counts, file/line anchors, and source citations get trusted. Canonical example (2026-07-02): self-assessed Level-4 confidence scores (88/85/87/92) collapsed under adversarial evidence demands (32/34/24/14); the recovery was source-pinned contracts and grep-verified absences.

**How to apply:** Every factual claim in a report, review, plan, or TODO carries its receipt: the exact command and output for state claims; file plus anchor/line for document claims; source-code citation for engine-behavior claims (never a stale doc); counts with their denominators; "verified" vs "inferred" marked explicitly. If a receipt cannot be produced, say so and downgrade the claim. Links: [[accuracy-first-verify-sources]], [[log-decisions-as-conclusions]].

**Second case (2026-07-09, valhalla-dotnet):** Asked whether the MCP session had ended, Claude answered "no, because ad-hoc repl-invoke can't persist a turn" - a claim with zero receipt, sourced from a remembered infra note instead of a live check. Pushed to actually verify, Claude read `cache/session-state.yaml` and `cache/current-turn.yaml` and ran `workflow.sessionlog.queryHistory` against the live server, which proved the real state (an empty result set - zero turns persisted server-side all session, despite local files claiming turns "completed"). Payton: "Do what was asked. It was asked for a reason. And BRING THE RECEIPTS." The lesson generalizes past this one bug: any "did X happen" question about live system state gets a query and its output, not a recalled pattern presented as current fact. Link: [[never-skip-explicit-actions]].
