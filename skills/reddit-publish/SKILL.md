---
name: Reddit Publish
description: Use ONLY when explicitly asked to PUBLISH a Reddit post or article publicly to a subreddit. Confirmation-gated public action. Drives Microsoft Edge over the CDP debug port via the RedditPublish PowerShell module. Triggers include "publish to r/X", "post this to reddit publicly".
version: 0.1.0
---

# Reddit Publish

**Publishing is public and hard to undo. Only do this when the user explicitly asks to publish, and
confirm the exact subreddit, title, and body first.** Uses the `RedditPublish` PowerShell module. For
saving drafts (the safe default), use the `reddit-draft` skill.

## Prerequisites

Same as `reddit-draft`: the `RedditPublish` module (PSModulePath or `F:\GitHub\RedditPublish`),
Microsoft Edge with the dedicated debug profile, and a completed Reddit login.

## Steps

1. Confirm with the user the exact subreddit, title, and body to publish. Do not proceed on assumption.

2. Import and connect:

   ```powershell
   Import-Module RedditPublish -ErrorAction SilentlyContinue
   if (-not (Get-Module RedditPublish)) { Import-Module F:\GitHub\RedditPublish\RedditPublish.psd1 -Force }
   $s = Connect-RedditSession
   ```

3. Publish. `Publish-RedditPost` is High-impact and prompts for confirmation; only confirm after the
   user has explicitly approved the content:

   ```powershell
   Publish-RedditPost -Session $s -Subreddit <name> -Title '<title>' -Body '<markdown body>'
   ```

   To fill the composer for a final visual review without publishing, add `-WhatIf`.

4. Report the resulting post URL/Result. If the Post button was blocked (required flair, karma/age
   gate, or unaccepted rules), tell the user; the module never force-submits.

## Guardrails

- Never publish without explicit user approval of the exact content and subreddit.
- Never batch-publish silently. Publish one post at a time unless the user directs otherwise.
- When intent is at all ambiguous, use `reddit-draft` instead and let the user publish manually.
