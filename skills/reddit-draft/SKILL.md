---
name: Reddit Draft
description: Use when asked to draft a Reddit post or article to a subreddit and save it as a draft (not publish). Drives Microsoft Edge over the CDP debug port via the RedditPublish PowerShell module. Triggers include "draft to r/X", "save a reddit draft", "draft these posts to reddit".
version: 0.1.0
---

# Reddit Draft

Save a Reddit post as a **draft** (never published) using the `RedditPublish` PowerShell module, which
drives Microsoft Edge over the Chrome DevTools Protocol remote-debugging port. For publishing publicly,
use the `reddit-publish` skill instead.

## Prerequisites

- The `RedditPublish` module (installed on the PSModulePath, or at `F:\GitHub\RedditPublish`).
- Microsoft Edge. A dedicated debug profile is used (`%LOCALAPPDATA%\EdgeAutomation`); on first use log
  into Reddit once in the Edge window that opens. The session then persists.
- PowerShell 7 (`pwsh`).

## Steps

1. Import the module and connect (launches/attaches Edge and waits for login on first use):

   ```powershell
   Import-Module RedditPublish -ErrorAction SilentlyContinue
   if (-not (Get-Module RedditPublish)) { Import-Module F:\GitHub\RedditPublish\RedditPublish.psd1 -Force }
   $s = Connect-RedditSession
   ```

2. Draft a single post, or a folder of article files (`r-*.md` or YAML-frontmatter):

   ```powershell
   New-RedditDraft -Session $s -Subreddit <name> -Title '<title>' -Body '<markdown body>'
   # or
   Invoke-RedditArticleBatch -Session $s -Path '<folder-or-file>'
   ```

3. Report the returned Community/Result per post. Leave Edge open so the user can review drafts at
   https://www.reddit.com/submit (Drafts). Disconnect with `Disconnect-RedditSession -Session $s`.

## Notes and guardrails

- Drafting never publishes. To fill the composer without saving, add `-WhatIf`.
- The body is written to Reddit's Markdown editor so links render.
- Flair, if specified, must be set manually (the module emits a warning).
- Only draft content the user has provided or approved; do not invent post text.
