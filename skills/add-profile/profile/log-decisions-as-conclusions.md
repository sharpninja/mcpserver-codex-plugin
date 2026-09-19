---
name: log-decisions-as-conclusions
description: "When logging MCP session work, record design decisions (conclusions + consequence) separately every sync — never fold them into actions or report \"0 decisions\"."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: a1eb3243-da80-4072-bc65-aeadd8ba062e
---

In the MCP session log, **decisions are conclusions/judgments and their consequences, not the steps taken**. They go in the `designDecisions` section, distinct from `actions`. Every sync-logs / wrap-up pass must enumerate the real judgment calls of the turn and log them. Never report "0 decisions (folded into actions)" — that phrasing is the failure mode itself.

**Why:** The user (Payton) has been trying to get Claude to log session *decisions* reliably since February 2026. The pattern across sessions: the keystroke trail (`actions`) gets captured while the *reasoning* (`designDecisions`) is under-recorded or buried inside action text. He pays for the reasoning, not just the steps. On 2026-06-29, the first sync-logs pass of a 12-round review loop logged 0 decisions and called them "folded into actions" — exactly the gap he has been fighting. He flagged it directly: "Decisions are about your conclusions, not the actions you take" and "It feels like you have been deliberately avoiding session logging... especially details of decisions."

**How to apply:** On every sync-logs/wrap-up, after appending actions, explicitly list the conclusions made this turn — each as *judgment + consequence + affected reqs/files* — and write them to `designDecisions`, append-only (read existing first, send existing+new, preserve order). A turn that made genuine judgment calls but logs zero decisions is a red flag: re-check before reporting. Heavy GETs can time out and render existing decisions blank — that is a read artifact, not an empty section; re-read before assuming you must recreate. Write the decision when it happens, do not reconstruct it later. Related write mechanics: [[mcp-session-log-rest-write-path]].
