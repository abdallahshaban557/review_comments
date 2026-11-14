// Copyright (c) 2026, Abdallah Shaban. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:jaspr/server.dart';
import 'package:jaspr_review_comments_example/jaspr_example.dart';
import 'package:review_comments_jaspr/review_comments_jaspr.dart';
import 'package:test/test.dart';

void main() {
  setUpAll(() {
    if (!Jaspr.isInitialized) {
      Jaspr.initializeApp();
    }
  });

  test('renders clean HTML without overlay by default', () async {
    final app = buildExampleContentApp();
    final rendered = await renderComponent(
      app,
      request: Request('GET', Uri.parse('http://localhost:8080/')),
    );
    final html = utf8.decode(rendered.body);
    expect(rendered.statusCode, equals(200));
    expect(html, contains('Visual Review for Jaspr'));
    expect(html, isNot(contains('dash-review-config')));
  });

  test('injects review overlay when ReviewConfig is enabled', () async {
    final app = buildExampleContentApp(
      config: const ReviewConfig(mode: 'local', serverPort: '4099'),
    );
    final rendered = await renderComponent(
      app,
      request: Request(
        'GET',
        Uri.parse('http://localhost:8080/getting-started'),
      ),
    );
    final html = utf8.decode(rendered.body);
    expect(rendered.statusCode, equals(200));
    expect(html, contains('Getting Started'));
    expect(html, contains('dash-review-config'));
    expect(html, contains('content/getting-started.md'));
  });

  test(
    'proxies same-origin /__dash_review/api/health alongside rendered pages',
    () async {
      final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => upstream.close(force: true));

      upstream.listen((req) async {
        req.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'ok': true,
              'site': 'jaspr-example',
              'feedbackFile': '.review_comments/feedback.md',
            }),
          );
        await req.response.close();
      });

      final handler = buildExampleServerHandler(
        config: ReviewConfig(mode: 'local', serverPort: '${upstream.port}'),
      );

      final healthRes = await handler(
        Request(
          'GET',
          Uri.parse('https://8080-dev.example.test/__dash_review/api/health'),
        ),
      );
      expect(healthRes.statusCode, equals(200));
      final healthJson =
          jsonDecode(await healthRes.readAsString()) as Map<String, Object?>;
      expect(healthJson['ok'], isTrue);
      expect(healthJson['site'], equals('jaspr-example'));
    },
  );
}
