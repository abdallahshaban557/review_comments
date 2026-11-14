// Copyright (c) 2026, Abdallah Shaban. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:review_comments_flutter/review_comments_flutter.dart';

class DemoMetricCard extends StatelessWidget {
  const DemoMetricCard({super.key, required this.title, required this.metric});

  final String title;
  final String metric;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(title),
            const SizedBox(height: 8),
            Text(metric),
          ],
        ),
      ),
    );
  }
}

void main() {
  group('ReviewCommentsConfig safety gates and route helpers', () {
    test('enables local mode on port 4099 by default in debug builds', () {
      const cfg = ReviewCommentsConfig(isReleaseMode: false);
      expect(cfg.isEnabled, isTrue);
      expect(cfg.effectiveMode, 'local');
      expect(cfg.effectiveServerPort, '4099');
      expect(cfg.serverOrigin, 'http://127.0.0.1:4099');
    });

    test('disables unconditionally when isProduction is true', () {
      const debugProd = ReviewCommentsConfig(
        isProduction: true,
        isReleaseMode: false,
        mode: 'local',
        enabled: true,
      );
      const previewProd = ReviewCommentsConfig(
        isProduction: true,
        isReleaseMode: true,
        mode: 'preview',
        enabled: true,
      );
      expect(debugProd.isEnabled, isFalse);
      expect(debugProd.effectiveMode, isEmpty);
      expect(previewProd.isEnabled, isFalse);
      expect(previewProd.effectiveMode, isEmpty);
    });

    test('disables in release mode unless mode is local or preview', () {
      const plainRelease = ReviewCommentsConfig(isReleaseMode: true);
      const localRelease = ReviewCommentsConfig(
        isReleaseMode: true,
        mode: 'local',
        serverPort: '4510',
      );
      const previewRelease = ReviewCommentsConfig(
        isReleaseMode: true,
        mode: 'preview',
        prNumber: '99',
        repo: 'flutter/website',
      );

      expect(plainRelease.isEnabled, isFalse);
      expect(plainRelease.effectiveMode, isEmpty);

      expect(localRelease.isEnabled, isTrue);
      expect(localRelease.effectiveMode, 'local');
      expect(localRelease.serverOrigin, 'http://127.0.0.1:4510');

      expect(previewRelease.isEnabled, isTrue);
      expect(previewRelease.effectiveMode, 'preview');
      expect(previewRelease.effectivePrNumber, '99');
      expect(previewRelease.effectiveRepo, 'flutter/website');
    });

    test('respects enabled: false and enableInDebug: false overrides', () {
      const explicitlyDisabled = ReviewCommentsConfig(
        isReleaseMode: false,
        enabled: false,
      );
      const debugOptOut = ReviewCommentsConfig(
        isReleaseMode: false,
        enableInDebug: false,
      );
      const modeOff = ReviewCommentsConfig(isReleaseMode: false, mode: 'off');

      expect(explicitlyDisabled.isEnabled, isFalse);
      expect(debugOptOut.isEnabled, isFalse);
      expect(modeOff.isEnabled, isFalse);
    });

    test('normalizes Flutter hash and path routes cleanly', () {
      expect(normalizeFlutterRoutePath(null), '/');
      expect(normalizeFlutterRoutePath(''), '/');
      expect(normalizeFlutterRoutePath('#/details?tab=metrics'), '/details');
      expect(normalizeFlutterRoutePath('/#/details/'), '/details');
      expect(normalizeFlutterRoutePath('details'), '/details');
      expect(
        normalizeFlutterRoutePath('/settings/profile/'),
        '/settings/profile',
      );
    });
  });

  group('Source URI normalization and selector formatting', () {
    test('normalizes file, package, org-dartlang-app, and http URIs', () {
      expect(
        normalizeWidgetSourceFile(
          'file:///workspace/examples/flutter_web_example/lib/main.dart',
        ),
        'lib/main.dart',
      );
      expect(
        normalizeWidgetSourceFile(
          'package:flutter_web_example/screens/home.dart',
        ),
        'lib/screens/home.dart',
      );
      expect(
        normalizeWidgetSourceFile(
          'org-dartlang-app:///packages/flutter_web_example/widgets/tile.dart',
        ),
        'lib/widgets/tile.dart',
      );
      expect(
        normalizeWidgetSourceFile(
          'http://127.0.0.1:8080/packages/flutter_web_example/main.dart',
        ),
        'lib/main.dart',
      );
    });

    test('filters SDK, pub-cache, and overlay internal URIs', () {
      expect(
        isFrameworkOrExternalCreationUri(
          'file:///sdk/packages/flutter/lib/src/material/card.dart',
        ),
        isTrue,
      );
      expect(
        isFrameworkOrExternalCreationUri('package:flutter/material.dart'),
        isTrue,
      );
      expect(
        isFrameworkOrExternalCreationUri(
          'package:review_comments_flutter/src/overlay_web.dart',
        ),
        isTrue,
      );
      expect(
        isFrameworkOrExternalCreationUri(
          'file:///workspace/examples/flutter_web_example/lib/main.dart',
        ),
        isFalse,
      );
    });

    test('formats and parses flutter selectors with and without keys', () {
      expect(
        formatFlutterSelector(
          widgetType: 'FilledButton',
          keyString: 'deploy-cta',
        ),
        'flutter:FilledButton[key=deploy-cta]',
      );
      expect(parseFlutterSelector('flutter:FilledButton[key=deploy-cta]'), (
        widgetType: 'FilledButton',
        keyString: 'deploy-cta',
      ));
      expect(parseFlutterSelector('flutter:Card'), (
        widgetType: 'Card',
        keyString: null,
      ));
      expect(parseFlutterSelector('div > span'), isNull);
    });
  });

  group('ReviewCommentsOverlay non-web stub', () {
    testWidgets('renders child cleanly with zero web side effects on VM', (
      tester,
    ) async {
      final observer = ReviewCommentsNavigatorObserver();
      await tester.pumpWidget(
        ReviewCommentsOverlay(
          navigatorObserver: observer,
          child: MaterialApp(
            navigatorObservers: <NavigatorObserver>[observer],
            home: const Scaffold(body: Text('VM Safe Render')),
          ),
        ),
      );

      expect(find.text('VM Safe Render'), findsOneWidget);
      expect(observer.currentRoute, '/');
    });
  });

  group('FlutterWidgetTreeInspector hit-testing, text, area, and scroll', () {
    testWidgets(
      'inspectPoint resolves buttons, cards, rich text, inputs, tooltips, semantics, and creation lines',
      (tester) async {
        final rootKey = GlobalKey();
        final textController = TextEditingController(text: 'us-central1-prod');
        addTearDown(textController.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: KeyedSubtree(
              key: rootKey,
              child: Scaffold(
                appBar: AppBar(title: const Text('Release Overview')),
                body: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const DemoMetricCard(
                        key: ValueKey<String>('uptime-card'),
                        title: 'Cluster Availability',
                        metric: '99.98%',
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        key: const ValueKey<String>('promote-btn'),
                        onPressed: () {},
                        child: const Text('Promote Build'),
                      ),
                      const SizedBox(height: 12),
                      RichText(
                        key: const ValueKey<String>('canary-rich-text'),
                        text: const TextSpan(
                          style: TextStyle(color: Colors.black, fontSize: 14),
                          text: 'Canary ',
                          children: <InlineSpan>[TextSpan(text: 'v2.4.0-rc1')],
                        ),
                      ),
                      const SizedBox(height: 12),
                      const SelectableText('commit-8f4d21a'),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: 240,
                        child: TextField(controller: textController),
                      ),
                      const SizedBox(height: 12),
                      const Tooltip(
                        message: 'Sync local diagnostics',
                        child: Icon(Icons.sync, size: 28),
                      ),
                      const SizedBox(height: 12),
                      Semantics(
                        label: 'Latency sparkline healthy',
                        child: const SizedBox(width: 80, height: 32),
                      ),
                      Offstage(
                        offstage: true,
                        child: FilledButton(
                          onPressed: () {},
                          child: const Text('Hidden Offstage Button'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );

        final inspector = FlutterWidgetTreeInspector(
          rootKey: rootKey,
          config: const ReviewCommentsConfig(),
        );

        // 1. FilledButton atomic hit (skips internal _RawMouseRegion / Padding / Semantics).
        final btnCenter = tester.getCenter(
          find.byKey(const ValueKey<String>('promote-btn')),
        );
        final btnHit = inspector.inspectPoint(btnCenter);
        expect(btnHit, isNotNull);
        expect(btnHit!.elementTag, 'FilledButton');
        expect(btnHit.selector, 'flutter:FilledButton[key=promote-btn]');
        expect(btnHit.selectedText, 'Promote Build');
        expect(btnHit.elementText, 'Promote Build');
        expect(btnHit.sourceFile, 'test/review_comments_flutter_test.dart');
        expect(btnHit.startLine, isNotNull);
        expect(btnHit.startLine, greaterThan(180));

        // 2. Card child Text vs custom DemoMetricCard surface padding.
        final titleCenter = tester.getCenter(find.text('Cluster Availability'));
        final titleHit = inspector.inspectPoint(titleCenter);
        expect(titleHit, isNotNull);
        expect(titleHit!.elementTag, 'Text');
        expect(titleHit.selectedText, 'Cluster Availability');

        final cardRect = tester.getRect(
          find.byKey(const ValueKey<String>('uptime-card')),
        );
        // Top-right inside the 20px card padding hits DemoMetricCard itself.
        final cardPaddingPoint = Offset(cardRect.right - 8, cardRect.top + 8);
        final cardHit = inspector.inspectPoint(cardPaddingPoint);
        expect(cardHit, isNotNull);
        expect(cardHit!.elementTag, 'DemoMetricCard');
        expect(cardHit.selector, 'flutter:DemoMetricCard[key=uptime-card]');
        expect(cardHit.elementText, 'Cluster Availability 99.98%');
        expect(cardHit.selectedText, 'Cluster Availability');

        // 3. RichText, SelectableText, TextField, Tooltip, Semantics.
        final richCenter = tester.getCenter(
          find.byKey(const ValueKey<String>('canary-rich-text')),
        );
        final richHit = inspector.inspectPoint(richCenter);
        expect(richHit, isNotNull);
        expect(richHit!.elementTag, 'RichText');
        expect(richHit.selectedText, 'Canary v2.4.0-rc1');

        final selectableCenter = tester.getCenter(find.byType(SelectableText));
        final selectableHit = inspector.inspectPoint(selectableCenter);
        expect(selectableHit, isNotNull);
        expect(selectableHit!.selectedText, 'commit-8f4d21a');

        final fieldCenter = tester.getCenter(find.byType(TextField));
        final fieldHit = inspector.inspectPoint(fieldCenter);
        expect(fieldHit, isNotNull);
        expect(fieldHit!.elementTag, 'TextField');
        expect(fieldHit.selectedText, 'us-central1-prod');

        final iconElement = tester.element(find.byType(Tooltip));
        expect(collectVisibleText(iconElement), 'Sync local diagnostics');

        final semCenter = tester.getCenter(
          find.bySemanticsLabel('Latency sparkline healthy'),
        );
        final semHit = inspector.inspectPoint(semCenter);
        expect(semHit, isNotNull);
        expect(semHit!.selectedText, 'Latency sparkline healthy');

        // 4. Long text capping at <= 240 chars.
        final longKey = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            home: KeyedSubtree(
              key: longKey,
              child: Scaffold(body: Text('A' * 400)),
            ),
          ),
        );
        final capped = collectVisibleText(longKey.currentContext! as Element);
        expect(capped.length, lessThanOrEqualTo(240));
        expect(capped.endsWith('...'), isTrue);
      },
    );

    testWidgets(
      'inspectArea aggregates visible text and computes viewport rectPct',
      (tester) async {
        final rootKey = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            home: KeyedSubtree(
              key: rootKey,
              child: const Scaffold(
                body: Padding(
                  padding: EdgeInsets.all(24),
                  child: DemoMetricCard(
                    key: ValueKey<String>('area-card'),
                    title: 'Error Budget',
                    metric: '99.95% remaining',
                  ),
                ),
              ),
            ),
          ),
        );

        final inspector = FlutterWidgetTreeInspector(
          rootKey: rootKey,
          config: const ReviewCommentsConfig(),
        );
        final cardRect = tester.getRect(
          find.byKey(const ValueKey<String>('area-card')),
        );

        final areaResult = inspector.inspectArea(
          cardRect,
          viewportSize: const Size(800, 600),
        );
        expect(areaResult, isNotNull);
        expect(areaResult!.selectedText, contains('Error Budget'));
        expect(areaResult.selectedText, contains('99.95% remaining'));
        expect(areaResult.sourceFile, 'test/review_comments_flutter_test.dart');
        expect(areaResult.startLine, isNotNull);
        expect(
          areaResult.rectPct['x'],
          closeTo((cardRect.left / 800) * 100, 0.1),
        );
        expect(
          areaResult.rectPct['y'],
          closeTo((cardRect.top / 600) * 100, 0.1),
        );
      },
    );

    testWidgets(
      'locateCommentRect tracks dynamic ListView scroll positions accurately',
      (tester) async {
        final rootKey = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            home: KeyedSubtree(
              key: rootKey,
              child: Scaffold(
                body: ListView.builder(
                  itemCount: 30,
                  itemExtent: 60,
                  itemBuilder: (context, index) => ListTile(
                    key: ValueKey<String>('row-$index'),
                    title: Text('Service Item #$index'),
                  ),
                ),
              ),
            ),
          ),
        );

        final inspector = FlutterWidgetTreeInspector(
          rootKey: rootKey,
          config: const ReviewCommentsConfig(),
        );

        final before = inspector.locateCommentRect(
          selector: 'flutter:ListTile[key=row-3]',
          elementText: 'Service Item #3',
        );
        expect(before, isNotNull);
        expect(before!.top, closeTo(180.0, 1.0));

        await tester.drag(find.byType(ListView), const Offset(0, -120));
        await tester.pumpAndSettle();

        final after = inspector.locateCommentRect(
          selector: 'flutter:ListTile[key=row-3]',
          elementText: 'Service Item #3',
        );
        expect(after, isNotNull);
        expect(after!.top, closeTo(60.0, 1.0));

        // Area comments intentionally return null to preserve freeform rectPct.
        expect(
          inspector.locateCommentRect(
            selector: 'flutter:ListTile[key=row-3]',
            anchorType: 'area',
          ),
          isNull,
        );
      },
    );

    testWidgets(
      'ReviewCommentsNavigatorObserver tracks routes and isolates offstage screens',
      (tester) async {
        final rootKey = GlobalKey();
        final observer = ReviewCommentsNavigatorObserver();

        await tester.pumpWidget(
          KeyedSubtree(
            key: rootKey,
            child: MaterialApp(
              navigatorObservers: <NavigatorObserver>[observer],
              initialRoute: '/',
              routes: <String, WidgetBuilder>{
                '/': (context) => Scaffold(
                  appBar: AppBar(title: const Text('Dashboard')),
                  body: Center(
                    child: FilledButton(
                      key: const ValueKey<String>('open-details-btn'),
                      onPressed: () => Navigator.pushNamed(context, '/details'),
                      child: const Text('Open Feature Details'),
                    ),
                  ),
                ),
                '/details': (context) => Scaffold(
                  appBar: AppBar(title: const Text('Feature Details')),
                  body: Center(
                    child: FilledButton(
                      key: const ValueKey<String>('back-btn'),
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Back to Dashboard'),
                    ),
                  ),
                ),
              },
            ),
          ),
        );

        final inspector = FlutterWidgetTreeInspector(
          rootKey: rootKey,
          config: const ReviewCommentsConfig(
            routeSourceFiles: <String, String>{
              '/': 'lib/main.dart',
              '/details': 'lib/screens/details.dart',
            },
          ),
          navigatorObserver: observer,
        );

        expect(inspector.getPageContext().pageUrl, '/');
        expect(inspector.getPageContext().pageTitle, 'Dashboard');
        expect(inspector.getPageContext().sourceFile, 'lib/main.dart');

        await tester.tap(
          find.byKey(const ValueKey<String>('open-details-btn')),
        );
        await tester.pumpAndSettle();

        expect(inspector.getPageContext().pageUrl, '/details');
        expect(inspector.getPageContext().pageTitle, 'Feature Details');
        expect(
          inspector.getPageContext().sourceFile,
          'lib/screens/details.dart',
        );

        // Exact button position hits '/details' button, never the offstage '/' button
        // located at the identical coordinates.
        final btnPos = tester.getCenter(
          find.byKey(const ValueKey<String>('back-btn')),
        );
        final centerHit = inspector.inspectPoint(btnPos);
        expect(centerHit, isNotNull);
        expect(centerHit!.selector, 'flutter:FilledButton[key=back-btn]');
        expect(
          inspector.locateCommentRect(
            selector: 'flutter:FilledButton[key=open-details-btn]',
          ),
          isNull,
        );

        await tester.tap(find.byKey(const ValueKey<String>('back-btn')));
        await tester.pumpAndSettle();

        expect(inspector.getPageContext().pageUrl, '/');
        expect(inspector.getPageContext().pageTitle, 'Dashboard');
      },
    );
  });
}
