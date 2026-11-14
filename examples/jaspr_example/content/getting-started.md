---
title: Getting Started
description: Add visual review comments to any Jaspr or jaspr_content site in one line.
---

## Quick Setup {#quick-setup}

Add `ReviewCommentsPageExtension(contentRootPrefix: 'content')` to your
`ContentApp` extensions list, or spread `buildReviewOverlayComponents(page)` at
the end of your custom `PageLayout`.

Production builds (`--dart-define=PRODUCTION=true`) emit zero overlay bytes.
