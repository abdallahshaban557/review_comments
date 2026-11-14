## 0.1.0

- Initial release of `review_comments_flutter`.
- Added `ReviewCommentsOverlay` with conditional multi-platform imports (`dart.library.js_interop` on Web; zero-cost passthrough widget on mobile, desktop, and VM tests).
- Added live Flutter `Element` / `RenderBox` / `CreationLocation` widget inspector bridge (`window.__REVIEW_COMMENTS_ADAPTER__`) supporting point inspection, area selection, visible text aggregation, exact Dart source file & line resolution, and live scroll pin tracking.
- Added `ReviewCommentsNavigatorObserver` and `ReviewCommentsConfig` with strict `PRODUCTION` and `kReleaseMode` safety gates.
