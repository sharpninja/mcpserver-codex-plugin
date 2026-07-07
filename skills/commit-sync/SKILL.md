---
name: Commit Sync
description: Use when the user asks for "commit-sync", "checkpoint", or "sync to origin" to pause the active task and commit/push dirty repo state to origin.
version: 0.1.0
---

Pause the active task first. Report the repo-scope dirty tree with `git status --short --untracked-files=all`, the current branch, and the origin remote via `git remote get-url origin`. Wait for explicit acknowledgement from the user before staging, committing, or pushing.

After acknowledgement, stage the full dirty tree with `git add -A -- .`, commit the complete scope, capture the commit SHA with `git rev-parse HEAD`, and push with `git push origin HEAD:<current-branch>`. Report the push result and the final clean/dirty status.

Never force push, rewrite history, rebase, reset, or discard unrelated user changes.
