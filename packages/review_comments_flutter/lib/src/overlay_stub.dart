// Copyright (c) 2026, Abdallah Shaban. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/widgets.dart';

import 'config.dart';
import 'navigator_observer.dart';

/// Wraps a Flutter application or route subtree to enable visual highlighting,
/// local coding-agent feedback, and GitHub PR review comments on Flutter Web.
///
/// On non-web platforms (iOS, Android, macOS, Windows, Linux, and VM widget
/// tests), this stub implementation is a zero-overhead passthrough returning
/// [child] directly.
class ReviewCommentsOverlay extends StatelessWidget {
  /// Creates a [ReviewCommentsOverlay] widget.
  const ReviewCommentsOverlay({
    super.key,
    required this.child,
    this.config = const ReviewCommentsConfig(),
    this.navigatorObserver,
    this.enabled,
  });

  /// The application or page widget subtree rendered beneath the overlay.
  final Widget child;

  /// Configuration and safety-gate parameters for the review overlay.
  final ReviewCommentsConfig config;

  /// Optional [ReviewCommentsNavigatorObserver] used to track active routes.
  final ReviewCommentsNavigatorObserver? navigatorObserver;

  /// Optional shorthand override for [ReviewCommentsConfig.enabled].
  final bool? enabled;

  @override
  Widget build(BuildContext context) => child;
}
