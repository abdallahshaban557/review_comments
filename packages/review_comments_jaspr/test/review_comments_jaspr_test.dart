// Copyright (c) 2026, Abdallah Shaban. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';

import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';
import 'package:jaspr_content/jaspr_content.dart';
import 'package:review_comments_jaspr/review_comments_jaspr.dart';
import 'package:test/test.dart';

Page _createTestPage({
  String path = 'ui/layout/index.md',
  String url = '/ui/layout',
  Map<String, Object?> pageData = const {'title': 'Layouts in Flutter'},
  Map<String, Object?> siteData = const {'title': 'Flutter Docs'},
}) {
  return Page(
    path: path,
    url: url,
    content: '# Test Page',
    initialData: {'page': pageData, 'site': siteData},
    config: const PageConfig(),
    loader: MemoryLoader(pages: const []),
  );
}

void main() {
  setUpAll(() {
    if (!Jaspr.isInitialized) {
      Jaspr.initializeApp();
    }
  });

  group('ReviewCommentsOverlay component', () {
    test('renders zero script bytes when disabled or in production', () async {
      final disabledHtml = utf8.decode(
        (await renderComponent(
          div([
            const ReviewCommentsOverlay(
              pageUrl: '/pricing',
              pageTitle: 'Pricing',
              sourceFile: 'lib/pricing_page.dart',
            ),
          ]),
          standalone: true,
        )).body,
      );
      expect(disabledHtml, isNot(contains('dash-review')));

      final prodHtml = utf8.decode(
        (await renderComponent(
          div([
            const ReviewCommentsOverlay(
              pageUrl: '/pricing',
              pageTitle: 'Pricing',
              sourceFile: 'lib/pricing_page.dart',
              config: ReviewConfig(
                mode: 'local',
                productionBuild: true,
                serverPort: '4099',
              ),
            ),
          ]),
          standalone: true,
        )).body,
      );
      expect(prodHtml, isNot(contains('dash-review')));
    });

    test('renders XSS-safe config and deferred script when enabled', () async {
      final html = utf8.decode(
        (await renderComponent(
          div([
            const ReviewCommentsOverlay(
              pageUrl: '/pricing',
              pageTitle: 'Pricing </script><script>alert(1)</script>',
              sourceFile: 'lib/pricing_page.dart',
              defaultSite: 'marketing',
              config: ReviewConfig(mode: 'local', serverPort: '4099'),
            ),
          ]),
          standalone: true,
        )).body,
      );

      expect(
        html,
        contains('<script id="dash-review-config" type="application/json">'),
      );
      expect(html, contains('<script id="dash-review-script" defer'));
      expect(html, isNot(contains('</script><script>alert(1)')));
      expect(html, contains(r'<\/script><script>alert(1)<\/script>'));
      expect(html, contains('http://127.0.0.1:4099'));
      expect(html, contains('lib/pricing_page.dart'));
    });
  });

  group('buildReviewOverlayComponents for jaspr_content layouts', () {
    test('returns empty list when disabled or productionBuild is true', () {
      final page = _createTestPage();
      expect(buildReviewOverlayComponents(page), isEmpty);
      expect(
        buildReviewOverlayComponents(
          page,
          config: const ReviewConfig(
            mode: 'preview',
            productionBuild: true,
            prNumber: '99',
          ),
        ),
        isEmpty,
      );
    });

    test(
      'supports DashLayout/DefaultLayout parameters and custom feedbackFile',
      () async {
        final page = _createTestPage(
          path: 'ai/index.md',
          url: '/ai',
          pageData: const {'title': 'Flutter & AI <!-- test -->'},
        );
        final components = buildReviewOverlayComponents(
          page,
          defaultSite: 'www',
          contentRootPrefix: 'sites/www/content',
          defaultRepo: 'flutter/website',
          feedbackFile: '.dash_review/feedback.md',
          config: const ReviewConfig(
            mode: 'preview',
            prNumber: '14030',
            commitSha: 'deadbeef',
          ),
        );

        expect(components, hasLength(2));

        final html = utf8.decode(
          (await renderComponent(
            Component.fragment(components),
            standalone: true,
          )).body,
        );
        expect(html, contains('sites/www/content/ai/index.md'));
        expect(html, contains('.dash_review/feedback.md'));
        expect(html, contains('flutter/website'));
        expect(html, contains('14030'));
        expect(html, isNot(contains('<!-- test -->')));
        expect(html, contains(r'\u003c!-- test -->'));
      },
    );
  });

  group('ReviewCommentsPageExtension', () {
    test('leaves nodes untouched when disabled', () async {
      final page = _createTestPage();
      const ext = ReviewCommentsPageExtension(contentRootPrefix: 'content');
      final initialNodes = <Node>[
        ElementNode('p', const {}, [TextNode('Hello world')]),
      ];

      final result = await ext.apply(page, initialNodes);
      expect(result, same(initialNodes));
      expect(result, hasLength(1));
    });

    test('appends ComponentNodes for config and script when enabled', () async {
      final page = _createTestPage(path: 'getting-started.md', url: '/start');
      const ext = ReviewCommentsPageExtension(
        defaultSite: 'docs',
        contentRootPrefix: 'content',
        config: ReviewConfig(mode: 'local', serverPort: '4099'),
      );
      final initialNodes = <Node>[
        ElementNode('p', const {}, [TextNode('Hello world')]),
      ];

      final result = await ext.apply(page, initialNodes);
      expect(result, hasLength(3));
      expect(result[1], isA<ComponentNode>());
      expect(result[2], isA<ComponentNode>());

      final html = utf8.decode(
        (await renderComponent(
          Component.fragment([
            for (final node in result.whereType<ComponentNode>())
              node.component,
          ]),
          standalone: true,
        )).body,
      );
      expect(html, contains('content/getting-started.md'));
      expect(html, contains('dash-review-host'));
    });
  });
}
