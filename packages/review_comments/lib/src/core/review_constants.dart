// Copyright (c) 2026, Abdallah Shaban. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Default loopback port tried first by the local review sync server.
const int defaultReviewServerPort = 4099;

/// Default repository-relative directory storing local review artifacts.
const String defaultReviewDirectory = '.review_comments';

/// Default repository-relative path to the agent-ready Markdown feedback file.
const String defaultReviewFeedbackFile = '.review_comments/feedback.md';

/// Default CLI command shown in local agent prompts when resolving comments.
const String defaultCliResolveCommand = 'dart run review_comments resolve';

/// DOM element ID for the `<script type="application/json">` configuration tag.
const String configElementId = 'dash-review-config';

/// DOM element ID for the deferred client overlay `<script>` tag.
const String scriptElementId = 'dash-review-script';

/// DOM element ID for an optional standalone `<style>` tag when injected.
const String stylesElementId = 'dash-review-styles';

/// DOM element ID for the Shadow DOM host mounted by the client overlay.
const String hostElementId = 'dash-review-host';
