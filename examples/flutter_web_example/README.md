# flutter_web_example

Two-route Flutter Web demo (`/` Release Dashboard and `/details` Feature
Details) showcasing `review_comments_flutter` with a **single dependency and
single import**.

## Running Locally with Agent Feedback Sync

```bash
dart run review_comments_flutter:review_comments serve -- flutter run -d chrome
```

## Building Web Targets

- **Local review release build**:
  ```bash
  flutter build web \
    --dart-define=REVIEW_COMMENTS_MODE=local \
    --dart-define=REVIEW_COMMENTS_SERVER_PORT=4099
  ```
- **GitHub PR preview build**:
  ```bash
  flutter build web \
    --dart-define=REVIEW_COMMENTS_MODE=preview \
    --dart-define=REVIEW_COMMENTS_PR_NUMBER=42 \
    --dart-define=REVIEW_COMMENTS_REPO=abdallahshaban557/review_comments
  ```
- **Production release build (zero review overlay bytes)**:
  ```bash
  flutter build web
  ```
