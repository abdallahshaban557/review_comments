// Copyright (c) 2026, Abdallah Shaban. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:jaspr/server.dart';
import 'package:jaspr_review_comments_example/jaspr_example.dart';
import 'package:review_comments_jaspr/review_comments_jaspr.dart';

void main() {
  Jaspr.initializeApp();
  registerReviewLocalProxyMiddleware();
  runApp(buildExampleContentApp());
}
