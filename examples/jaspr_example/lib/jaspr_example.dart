// Copyright (c) 2026, Abdallah Shaban. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';
import 'package:jaspr_content/jaspr_content.dart';
import 'package:review_comments_jaspr/review_comments_jaspr.dart';
import 'package:review_comments_jaspr/server.dart';

/// Example `jaspr_content` layout wiring [buildReviewOverlayComponents] into
/// `<body>` while emitting zero bytes in production builds.
final class ExampleDocsLayout extends PageLayoutBase {
  /// Creates an [ExampleDocsLayout].
  const ExampleDocsLayout({this.config});

  /// Optional explicit [ReviewConfig] override (used in tests or previews).
  final ReviewConfig? config;

  @override
  Pattern get name => 'default';

  @override
  Iterable<Component> buildHead(Page page) sync* {
    yield* super.buildHead(page);
    yield Style(
      styles: [
        css('body').styles(
          margin: Spacing.zero,
          fontFamily: const FontFamily.list([
            FontFamily('system-ui'),
            FontFamilies.sansSerif,
          ]),
          backgroundColor: const Color('#f8fafc'),
          color: const Color('#0f172a'),
        ),
        css('main').styles(
          maxWidth: 760.px,
          margin: Spacing.symmetric(horizontal: Unit.auto, vertical: 40.px),
          padding: Spacing.symmetric(horizontal: 24.px, vertical: 32.px),
          backgroundColor: Colors.white,
          radius: BorderRadius.circular(14.px),
        ),
        css('nav').styles(
          display: Display.flex,
          gap: Gap.all(16.px),
          margin: Spacing.only(bottom: 24.px),
        ),
      ],
    );
  }

  @override
  Component buildBody(Page page, Component child) {
    final title = (page.data.page['title'] as String?) ?? 'Jaspr Example';
    return Component.fragment([
      main_([
        nav([
          a(href: '/', [Component.text('Home')]),
          a(href: '/getting-started', [Component.text('Getting Started')]),
        ]),
        h1(id: 'page-title', [Component.text(title)]),
        child,
      ]),
      ...buildReviewOverlayComponents(
        page,
        defaultSite: 'jaspr-example',
        contentRootPrefix: 'content',
        defaultRepo: 'abdallahshaban/review_comments',
        config: config,
      ),
    ]);
  }
}

/// Builds the example `ContentApp` configured with local Markdown pages and
/// [ExampleDocsLayout].
ContentApp buildExampleContentApp({
  String contentDirectory = 'content',
  ReviewConfig? config,
}) {
  return ContentApp.custom(
    loaders: [FilesystemLoader(contentDirectory)],
    configResolver: PageConfig.all(
      parsers: const [MarkdownParser()],
      layouts: [ExampleDocsLayout(config: config)],
    ),
  );
}

/// Builds a `shelf` [Handler] for the example app wrapped with
/// [reviewLocalProxyMiddleware] so `/__dash_review/api/*` requests are proxied
/// over the same origin.
Handler buildExampleServerHandler({
  String contentDirectory = 'content',
  ReviewConfig? config,
}) {
  final app = buildExampleContentApp(
    contentDirectory: contentDirectory,
    config: config,
  );
  final proxy = reviewLocalProxyMiddleware(config: config);
  return proxy(serveApp((_, render) => render(app)));
}
