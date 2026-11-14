---
title: Visual Review for Jaspr
description: Highlight text or elements on staged previews and local dev servers.
---

## Overview {#overview}

Welcome to the `review_comments_jaspr` demo site. Select any sentence on this
page to pop up the **Comment on selection** pill, or press `Alt+C` to inspect
elements and drag region boxes.

## Agent & PR Workflow {#workflow}

- **Local Mode**: Syncs every comment to `.review_comments/feedback.md` with
  resolved Markdown file paths and line numbers for coding agents.
- **PR Preview Mode**: Maps highlighted prose to the exact RIGHT-side GitHub PR
  diff line or copies a shell-safe `gh` CLI command.
