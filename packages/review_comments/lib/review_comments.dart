// Copyright (c) 2026, Abdallah Shaban. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Multi-platform (Web, Wasm, and VM) configuration, comment models, XSS-safe
/// serialization, Shadow DOM styles, and client overlay runtime for visual
/// review and GitHub PR diff comments.
///
/// For the local `127.0.0.1` sync server, source-line locator, and CLI runner,
/// import `package:review_comments/cli.dart`.
library;

export 'src/core/review_client_script.dart'
    show buildReviewClientScript, reviewOverlayClientScript;
export 'src/core/review_comment_model.dart'
    show ReviewCommentModel, computeReviewCommentCounts, normalizeReviewPageUrl;
export 'src/core/review_config.dart'
    show ReviewConfig, encodeReviewJsonForHtml, normalizeReviewSourceFile;
export 'src/core/review_constants.dart'
    show
        configElementId,
        defaultCliResolveCommand,
        defaultReviewDirectory,
        defaultReviewFeedbackFile,
        defaultReviewServerPort,
        hostElementId,
        scriptElementId,
        stylesElementId;
export 'src/core/review_styles.dart' show reviewOverlayStyles;
