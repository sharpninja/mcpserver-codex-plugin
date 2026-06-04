---
name: commit-sync
description: Pause current Codex work and commit/push dirty repository state when asked for "commit-sync", "checkpoint", or "sync to origin".
---

Pause first. Report the repo-scope dirty tree with `git status --short --untracked-files=all`, the current branch, and `git remote get-url origin`. Wait for explicit acknowledgement before staging, committing, or pushing.

After acknowledgement, stage the full dirty tree with `git add -A -- .`, commit the complete scope, capture the commit SHA with `git rev-parse HEAD`, and push with `git push origin HEAD:<current-branch>`. Report the push result and final clean/dirty status.

Never force push, rewrite history, rebase, reset, or drop unrelated user changes.
