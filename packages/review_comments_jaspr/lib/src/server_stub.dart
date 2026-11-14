// Copyright (c) 2026, Abdallah Shaban. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:review_comments/review_comments.dart';

/// URL prefix mounted on Jaspr `ServerApp` for same-origin local review API
/// calls.
const String reviewProxyPathPrefix = '/__dash_review';

/// Browser no-op stub for `registerReviewLocalProxyMiddleware` when
/// `package:review_comments_jaspr/review_comments_jaspr.dart` is imported in a
/// client bundle.
void registerReviewLocalProxyMiddleware({ReviewConfig? config}) {}
