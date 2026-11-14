# review_comments_jaspr

All-in-one Jaspr and `jaspr_content` plugin for visual review comments,
same-origin local coding-agent sync (`.review_comments/feedback.md` + CLI), and
staged GitHub PR inline diff comments—requiring **only 1 dependency and 1
import**.

## Installation (1 Dependency)

```yaml
dependencies:
  review_comments_jaspr: ^0.1.0
```

## Quick Start (1 Import)

```dart
import 'package:jaspr/server.dart';
import 'package:jaspr_content/jaspr_content.dart';
import 'package:review_comments_jaspr/review_comments_jaspr.dart';

void main() {
  Jaspr.initializeApp(options: defaultServerOptions);
  registerReviewLocalProxyMiddleware();

  runApp(
    ContentApp(
      extensions: [
        const ReviewCommentsPageExtension(contentRootPrefix: 'content'),
      ],
    ),
  );
}
```

You can also mount the overlay inside a custom `PageLayout`
(`...buildReviewOverlayComponents(page, contentRootPrefix: 'content')`) or any
standalone Jaspr `Document` (`const ReviewCommentsOverlay(...)`).

## Local Server & Coding-Agent CLI (Included)

```bash
# Serve Jaspr with live .review_comments/feedback.md sync:
dart run review_comments_jaspr:review_comments serve -- jaspr serve

# Inspect, export prompt, resolve, or clear comments:
dart run review_comments_jaspr:review_comments list
dart run review_comments_jaspr:review_comments prompt
dart run review_comments_jaspr:review_comments resolve <id | --all>
dart run review_comments_jaspr:review_comments clear
```

Production (`--dart-define=PRODUCTION=true`) and standard builds without
`REVIEW_COMMENTS_MODE` (`local` or `preview`) emit zero bytes and register no
middleware.
