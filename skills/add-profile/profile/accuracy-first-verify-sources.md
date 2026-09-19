---
name: accuracy-first-verify-sources
description: "feedback - \"accuracy trumps all, if unsure ask\"; verify from the authoritative artifact not stale markers; admit failures plainly"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: a1eb3243-da80-4072-bc65-aeadd8ba062e
---

"**Accuracy trumps all. If you are unsure, ask me.**" (verbatim, recurring instruction.)

**Why:** Payton corrects wrong info sharply ("that is old and bad info. Where did you get it?"). He caught a plugin version cited from a stale marker field when the truth was in the plugin's own `.version` / `plugin.json`. He also expects honest admission when something is broken (e.g. the session-log and failsafe writes not persisting) rather than reassurance that it worked.

**How to apply:** Read facts from the authoritative source (the plugin, file, or DB itself), not a convenient cached or marker value. Mark observation vs inference. When unsure, ask before acting. Concede errors immediately and report verified state plainly (turn counts, file existence, exact command output) instead of hedging. Surface stale or drifted data when you spot it. Links: [[user-payton-byrd]], [[log-decisions-as-conclusions]].
