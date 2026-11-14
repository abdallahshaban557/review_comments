## 0.1.0

- Initial release of `review_comments_core`.
- Added `ReviewConfig` supporting `REVIEW_COMMENTS_*` and legacy `DASH_REVIEW_*`
  compile-time `--dart-define`s, runtime configuration, and a hard `PRODUCTION`
  safety gate.
- Added `ReviewCommentModel`, URL/source-file normalization helpers, and
  XSS-safe `encodeReviewJsonForHtml`.
- Added Shadow DOM styles (`reviewOverlayStyles`) and client overlay runtime
  (`reviewOverlayClientScript`) with `window.__REVIEW_COMMENTS_ADAPTER__` hooks
  for canvas/WebGL frameworks such as Flutter Web.
