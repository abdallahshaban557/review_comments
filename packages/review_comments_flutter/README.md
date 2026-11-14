# review_comments_flutter

All-in-one visual highlight, local coding-agent feedback CLI, and GitHub PR diff
comment overlay for **Flutter Web** applications—requiring **only 1 dependency
and 1 import**.

Flutter Web renders onto `<flutter-view>` (CanvasKit / Skwasm), where standard
DOM inspection only sees a `<canvas>`. `review_comments_flutter` bridges
Flutter's live `Element`, `RenderBox`, `CreationLocation`, and `Navigator`
trees into the shared Shadow-DOM review overlay.

## Installation (1 Dependency)

```yaml
dependencies:
  review_comments_flutter: ^0.1.0
```

## Quick Start (1 Import)

```dart
import 'package:flutter/material.dart';
import 'package:review_comments_flutter/review_comments_flutter.dart';

final _reviewObserver = ReviewCommentsNavigatorObserver();

void main() {
  runApp(
    ReviewCommentsOverlay(
      navigatorObserver: _reviewObserver,
      child: MaterialApp(
        navigatorObservers: [_reviewObserver],
        home: const MyHomePage(),
      ),
    ),
  );
}
```

### Local Review with Coding Agents

Start the local sync server and launch Flutter Web in one command (bundled right
inside `review_comments_flutter`):

```bash
dart run review_comments_flutter:review_comments serve -- flutter run -d chrome
```

Manage local feedback from the CLI:

```bash
dart run review_comments_flutter:review_comments list
dart run review_comments_flutter:review_comments prompt
dart run review_comments_flutter:review_comments resolve <id | --all>
dart run review_comments_flutter:review_comments clear
```

### Staged PR Preview Mode

```bash
flutter build web \
  --dart-define=REVIEW_COMMENTS_MODE=preview \
  --dart-define=REVIEW_COMMENTS_PR_NUMBER=42 \
  --dart-define=REVIEW_COMMENTS_REPO=owner/repo \
  --dart-define=REVIEW_COMMENTS_COMMIT_SHA=$(git rev-parse HEAD)
```
