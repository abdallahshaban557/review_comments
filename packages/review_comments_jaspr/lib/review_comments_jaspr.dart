// Copyright (c) 2026, Abdallah Shaban. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Single-import Jaspr and `jaspr_content` entry point for visual review
/// overlays, same-origin local sync proxy middleware, and inline GitHub PR diff
/// comments.
library;

export 'package:review_comments/review_comments.dart';

export 'src/jaspr_overlay.dart'
    show
        ReviewCommentsOverlay,
        ReviewCommentsPageExtension,
        buildReviewOverlayComponents,
        buildReviewPageConfigMap,
        buildReviewScriptComponents;
export 'src/server_stub.dart'
    if (dart.library.io) 'server.dart'
    show registerReviewLocalProxyMiddleware, reviewProxyPathPrefix;
