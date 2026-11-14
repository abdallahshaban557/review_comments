// Copyright (c) 2026, Abdallah Shaban. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_web_example/main.dart';
import 'package:material_ui/material_ui.dart';
import 'package:review_comments_flutter/review_comments_flutter.dart';

void main() {
  testWidgets(
    'navigates between Dashboard (/) and Feature Details (/details)',
    (tester) async {
      final observer = ReviewCommentsNavigatorObserver();
      await tester.pumpWidget(
        FlutterReviewDemoApp(navigatorObserver: observer),
      );

      expect(find.text('Release v3.50 Rollout Overview'), findsOneWidget);
      expect(find.text('12,480'), findsOneWidget);
      expect(observer.currentRoute, '/');

      await tester.tap(find.byKey(const ValueKey<String>('open-details-btn')));
      await tester.pumpAndSettle();

      expect(
        find.text('Shadow-DOM & Flutter Element Inspector Bridge'),
        findsOneWidget,
      );
      expect(observer.currentRoute, '/details');

      await tester.tap(
        find.byKey(const ValueKey<String>('back-to-dashboard-btn')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Release v3.50 Rollout Overview'), findsOneWidget);
      expect(observer.currentRoute, '/');
    },
  );
}
