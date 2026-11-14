# Jaspr Visual Review Example

Minimal runnable [Jaspr](https://jaspr.site) +
[`jaspr_content`](https://docs.jaspr.site/content) site demonstrating
`package:review_comments_jaspr` with **1 dependency and 1 import**.

## Running Locally with Coding-Agent Sync

```bash
dart run review_comments_jaspr:review_comments serve -- \
  dart run \
    --dart-define=REVIEW_COMMENTS_MODE=local \
    --dart-define=REVIEW_COMMENTS_SERVER_PORT=4099 \
    bin/main.dart
```

Open `http://localhost:8080`, highlight any sentence or press `Alt+C` to
inspect an element, and add a comment. Requests route over same-origin
`/__dash_review/api/*` on port `8080`, updating `.review_comments/feedback.md`
and `.review_comments/comments.json`.

## Running in Staged PR Preview Mode

```bash
dart run \
  --dart-define=REVIEW_COMMENTS_MODE=preview \
  --dart-define=REVIEW_COMMENTS_PR_NUMBER=42 \
  --dart-define=REVIEW_COMMENTS_REPO=abdallahshaban557/review_comments \
  bin/main.dart
```
