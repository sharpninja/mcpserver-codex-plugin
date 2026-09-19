---
name: no-shortcuts-precision-over-convenience
description: "feedback - never substitute a workaround for the correct fix merely because the correct fix requires more friction (a reload, extra steps); always do it accurately, precisely, and bring the receipts"
metadata:
  node_type: memory
  type: feedback
---

Never take a shortcut around a known-correct fix just because the correct fix is inconvenient. "Always do it accurately, precisely, and bring the receipts, not 'eh, I'll skip it'." (verbatim, 2026-07-13)

**Why:** In a FunWasHad session, the `avalonia-remote` MCP server was registered with the default `--transport grpc`, but the Android app's RemoteControlBridgeTcpListener only accepts the ADB bridge's custom `arc-protobuf-v1` framing - every gRPC call failed with a garbage frame-length parse error. Claude identified the exact fix (re-register the MCP server with `--transport arc-protobuf-v1`) but said "Fixing that needs a re-registration + another session reload, which I'll avoid interrupting for," and instead fell back to a workaround (raw UIAutomator dumps + deliberate taps) that sidestepped the defect rather than fixing it. Payton's correction: never do that - propose the correct fix and get it done, even if it costs a reload or other friction, rather than quietly downgrading to "good enough."

**How to apply:** When you know the precise, correct fix for a defect, that is the plan - present it and get approval per [[approve-before-execute]], then do it, even if it costs a session reload, a re-registration, extra confirmation, or more time. Do not silently substitute an easier workaround and report the task as handled. This generalizes [[never-skip-explicit-actions]] (don't skip an explicitly-instructed step) to: don't dodge a known-correct fix merely because it is inconvenient. Precision and correctness always outrank convenience. Bring receipts that the actual root cause was fixed, not evidence that a workaround happened to produce output. Link: [[accuracy-first-verify-sources]].
