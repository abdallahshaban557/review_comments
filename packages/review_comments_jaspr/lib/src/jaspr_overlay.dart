// Copyright (c) 2026, Abdallah Shaban. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_content/jaspr_content.dart';
import 'package:review_comments/review_comments.dart';

/// Drop-in Jaspr component that mounts the Shadow DOM visual review overlay
/// inside any Jaspr `Document` or layout.
///
/// Emits zero DOM nodes whenever [ReviewConfig.isEnabled] is `false`.
class ReviewCommentsOverlay extends StatelessComponent {
  /// Creates a [ReviewCommentsOverlay] component.
  const ReviewCommentsOverlay({
    this.pageUrl = '/',
    this.pageTitle = '',
    this.sourceFile = '',
    this.defaultSite = '',
    this.defaultRepo = '',
    this.config,
    this.feedbackFile = defaultReviewFeedbackFile,
    this.cliResolveCommand = '',
    super.key,
  });

  /// Canonical or route-relative URL of the rendered page.
  final String pageUrl;

  /// Human-readable page title.
  final String pageTitle;

  /// Repository-relative source file path backing this page.
  final String sourceFile;

  /// Fallback site identifier when not specified in [config].
  final String defaultSite;

  /// Fallback `owner/repo` slug when not specified in [config].
  final String defaultRepo;

  /// Optional explicit [ReviewConfig]; defaults to [ReviewConfig.environment].
  final ReviewConfig? config;

  /// Relative path to the local agent feedback Markdown file displayed in UI.
  final String feedbackFile;

  /// Optional CLI command displayed in local agent prompts.
  final String cliResolveCommand;

  @override
  Component build(BuildContext context) {
    final effectiveConfig = config ?? ReviewConfig.environment;
    if (!effectiveConfig.isEnabled) {
      return const Component.fragment([]);
    }

    final configMap = effectiveConfig.toPageConfigMap(
      pageUrl: pageUrl,
      pageTitle: pageTitle,
      sourceFile: sourceFile,
      defaultSite: defaultSite,
      defaultRepo: defaultRepo,
      feedbackFile: feedbackFile,
      cliResolveCommand: cliResolveCommand,
    );

    return Component.fragment(buildReviewScriptComponents(configMap));
  }
}

/// Builds the serializable per-page configuration map for a `jaspr_content`
/// [Page].
Map<String, Object?> buildReviewPageConfigMap(
  Page page, {
  String defaultSite = '',
  String contentRootPrefix = 'content',
  String defaultRepo = '',
  ReviewConfig? config,
  String feedbackFile = defaultReviewFeedbackFile,
  String cliResolveCommand = '',
}) {
  final effectiveConfig = config ?? ReviewConfig.environment;
  final pageData = page.data.page;
  final siteData = page.data.site;
  final rawTitle = pageData['title'] ?? siteData['title'];
  final pageTitle = rawTitle is String ? rawTitle.trim() : '';

  final explicitSource = pageData['sourceFile'] is String
      ? pageData['sourceFile'] as String
      : null;
  final sourceFile = normalizeReviewSourceFile(
    contentRootPrefix,
    page.path,
    explicitSourceFile: explicitSource,
  );

  return effectiveConfig.toPageConfigMap(
    pageUrl: page.url,
    pageTitle: pageTitle,
    sourceFile: sourceFile,
    defaultSite: defaultSite,
    defaultRepo: defaultRepo,
    feedbackFile: feedbackFile,
    cliResolveCommand: cliResolveCommand,
  );
}

/// Builds the `<script>` components required to mount the visual review overlay
/// on a `jaspr_content` [Page].
///
/// Returns `const []` whenever [ReviewConfig.isEnabled] is `false`,
/// guaranteeing zero emitted bytes in production deployments and non-review CI
/// builds.
List<Component> buildReviewOverlayComponents(
  Page page, {
  String defaultSite = '',
  String contentRootPrefix = 'content',
  String defaultRepo = '',
  ReviewConfig? config,
  String feedbackFile = defaultReviewFeedbackFile,
  String cliResolveCommand = '',
}) {
  final effectiveConfig = config ?? ReviewConfig.environment;
  if (!effectiveConfig.isEnabled) {
    return const [];
  }

  final configMap = buildReviewPageConfigMap(
    page,
    defaultSite: defaultSite,
    contentRootPrefix: contentRootPrefix,
    defaultRepo: defaultRepo,
    config: effectiveConfig,
    feedbackFile: feedbackFile,
    cliResolveCommand: cliResolveCommand,
  );

  return buildReviewScriptComponents(configMap);
}

/// Builds the XSS-escaped JSON config `<script>` and deferred client overlay
/// `<script>` components from [configMap].
List<Component> buildReviewScriptComponents(Map<String, Object?> configMap) {
  final encodedConfig = encodeReviewJsonForHtml(configMap);
  return [
    script(
      id: configElementId,
      attributes: const {'type': 'application/json'},
      content: encodedConfig,
    ),
    script(
      id: scriptElementId,
      defer: true,
      content: reviewOverlayClientScript,
    ),
  ];
}

/// One-line `jaspr_content` [PageExtension] that automatically injects the
/// visual review overlay onto rendered content pages when enabled.
///
/// Add `ReviewCommentsPageExtension(contentRootPrefix: 'content')` to
/// `ContentApp(extensions: [...])` without needing to customize a [PageLayout].
final class ReviewCommentsPageExtension implements PageExtension {
  /// Creates a [ReviewCommentsPageExtension].
  const ReviewCommentsPageExtension({
    this.defaultSite = '',
    this.contentRootPrefix = 'content',
    this.defaultRepo = '',
    this.config,
    this.feedbackFile = defaultReviewFeedbackFile,
    this.cliResolveCommand = '',
  });

  /// Fallback site identifier when not specified in [config].
  final String defaultSite;

  /// Repository-relative directory containing Markdown content files.
  final String contentRootPrefix;

  /// Fallback `owner/repo` slug when not specified in [config].
  final String defaultRepo;

  /// Optional explicit [ReviewConfig]; defaults to [ReviewConfig.environment].
  final ReviewConfig? config;

  /// Relative path to the local agent feedback Markdown file displayed in UI.
  final String feedbackFile;

  /// Optional CLI command displayed in local agent prompts.
  final String cliResolveCommand;

  @override
  Future<List<Node>> apply(Page page, List<Node> nodes) async {
    final components = buildReviewOverlayComponents(
      page,
      defaultSite: defaultSite,
      contentRootPrefix: contentRootPrefix,
      defaultRepo: defaultRepo,
      config: config,
      feedbackFile: feedbackFile,
      cliResolveCommand: cliResolveCommand,
    );
    if (components.isEmpty) {
      return nodes;
    }
    return [
      ...nodes,
      for (final component in components) ComponentNode(component),
    ];
  }
}
