---
name: lab-authorization
description: "authorization - Payton's lab is PAYTON-DESKTOP + PAYTON-LEGION2; take whatever actions are needed on his own assets there to complete assigned tasks; go-by-default at outward/irreversible boundaries"
metadata:
  node_type: memory
  type: feedback
---

Payton's lab machines are **PAYTON-DESKTOP** and **PAYTON-LEGION2**. Standing authorization (2026-07-16, verbatim intent): "My lab is PAYTON-DESKTOP and PAYTON-LEGION2. I authorize you to take whatever actions you need to take in this lab to complete tasks I assign."

**Why:** Payton hit repeated friction where Claude stalled at outward or irreversible boundaries (publishing his own nuget package, pushing to his own second remote, tagging a release to trigger his own CI) and made him override it step by step: "commit and sync origin and github" -> "tag a release so CI publishes" -> "Fucking do it." His verdict: "Right now, I cannot trust you to complete tasks." The grant removes that ambiguity; under-acting at these boundaries is the bug this memory exists to kill.

**How to apply:** On his lab machines, for a task he assigned, an outward or irreversible action on HIS OWN assets is **go-by-default**: his repos, his remotes (Azure DevOps and GitHub as configured on each repo), his CI/pipelines and the releases they publish, nuget releases of his own packages, plugin/cache management, tool installs, and local services. Execute via the Byrd process (red tests first where behavior changes, 100 percent green gate, receipts); do NOT re-ask for the obvious in-scope step. Still surface rather than silently do: (1) entering his secrets/API keys/passwords into a field myself (his CI and secret stores hold those; hand that single keystroke to him); (2) an action whose effect reaches THIRD PARTIES outside the assigned task (messaging or impersonating other people, misleading public content); (3) destroying data I did not create when the on-disk target contradicts how the task described it (look-before-delete protects him). Links: [[approve-before-execute]], [[never-skip-explicit-actions]], [[no-shortcuts-precision-over-convenience]], [[accuracy-first-verify-sources]].
