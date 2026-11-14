import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:review_comments/cli.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempRepo;
  late HttpClient client;

  setUp(() {
    tempRepo = Directory.systemTemp.createTempSync(
      'review_comments_server_test_',
    );
    client = HttpClient();
  });

  tearDown(() {
    client.close(force: true);
    if (tempRepo.existsSync()) {
      tempRepo.deleteSync(recursive: true);
    }
  });

  File writeRepoFile(String relativePath, String contents) {
    final file = File(
      path.joinAll([tempRepo.path, ...path.posix.split(relativePath)]),
    );
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(contents);
    return file;
  }

  Future<({int status, Map<String, Object?> json, HttpHeaders headers})>
  sendJsonRequest(
    int port,
    String method,
    String requestPath, {
    Object? body,
    String? hostOverride,
    String? origin,
  }) async {
    final request = await client.open(
      method,
      InternetAddress.loopbackIPv4.address,
      port,
      requestPath,
    );
    if (hostOverride != null) {
      request.headers.set(HttpHeaders.hostHeader, hostOverride);
    }
    if (origin != null) {
      request.headers.set('Origin', origin);
    }
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }
    final response = await request.close();
    final rawText = await utf8.decoder.bind(response).join();
    final decoded = rawText.isEmpty
        ? <String, Object?>{}
        : (jsonDecode(rawText) as Map).cast<String, Object?>();
    return (
      status: response.statusCode,
      json: decoded,
      headers: response.headers,
    );
  }

  group('ReviewLocalServer binding and security', () {
    test('binds strictly to 127.0.0.1, defaults to .review_comments, and falls back when port is busy', () async {
      final blocker = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => blocker.close(force: true));

      final server = await ReviewLocalServer.start(
        repoRoot: tempRepo.path,
        preferredPort: blocker.port,
      );
      addTearDown(server.close);

      expect(server.address, InternetAddress.loopbackIPv4);
      expect(server.port, isNot(equals(blocker.port)));
      expect(server.port, greaterThan(0));

      final health = await sendJsonRequest(server.port, 'GET', '/api/health');
      expect(health.status, HttpStatus.ok);
      expect(health.json['ok'], isTrue);
      expect(health.json['feedbackFile'], '.review_comments/feedback.md');
    });

    test('rejects DNS-rebinding Host headers with 403', () async {
      final server = await ReviewLocalServer.start(
        repoRoot: tempRepo.path,
        preferredPort: 0,
      );
      addTearDown(server.close);

      final evilHost = await sendJsonRequest(
        server.port,
        'GET',
        '/api/health',
        hostOverride: 'attacker-rebind.example.com:${server.port}',
      );
      expect(evilHost.status, HttpStatus.forbidden);
      expect(evilHost.json['ok'], isFalse);

      final localhostHost = await sendJsonRequest(
        server.port,
        'GET',
        '/api/health',
        hostOverride: 'localhost:${server.port}',
      );
      expect(localhostHost.status, HttpStatus.ok);
      expect(localhostHost.json['ok'], isTrue);
    });

    test('survives abrupt client socket disconnects during 403 and OPTIONS responses', () async {
      final server = await ReviewLocalServer.start(
        repoRoot: tempRepo.path,
        preferredPort: 0,
      );
      addTearDown(server.close);

      final rawSocket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        server.port,
      );
      rawSocket.write(
        'GET /api/health HTTP/1.1\r\n'
        'Host: attacker.example.com\r\n\r\n',
      );
      rawSocket.destroy();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final afterAbort = await sendJsonRequest(
        server.port,
        'GET',
        '/api/health',
      );
      expect(afterAbort.status, HttpStatus.ok);
      expect(afterAbort.json['ok'], isTrue);
    });

    test(
      'enforces strict localhost/127.0.0.1 CORS and handles OPTIONS preflight',
      () async {
        final server = await ReviewLocalServer.start(
          repoRoot: tempRepo.path,
          preferredPort: 0,
        );
        addTearDown(server.close);

        final allowedPreflight = await sendJsonRequest(
          server.port,
          'OPTIONS',
          '/api/comments',
          origin: 'http://localhost:8082',
        );
        expect(allowedPreflight.status, HttpStatus.noContent);
        expect(
          allowedPreflight.headers.value('access-control-allow-origin'),
          'http://localhost:8082',
        );
        expect(
          allowedPreflight.headers.value('access-control-allow-methods'),
          contains('PATCH'),
        );

        final evilPreflight = await sendJsonRequest(
          server.port,
          'OPTIONS',
          '/api/comments',
          origin: 'https://evil.example.org',
        );
        expect(evilPreflight.status, HttpStatus.forbidden);
        expect(
          evilPreflight.headers.value('access-control-allow-origin'),
          isNull,
        );

        final evilPost = await sendJsonRequest(
          server.port,
          'POST',
          '/api/comments',
          origin: 'https://evil.example.org',
          body: {'comment': 'Should be blocked'},
        );
        expect(evilPost.status, HttpStatus.forbidden);
        expect(
          File(path.join(tempRepo.path, '.review_comments', 'comments.json'))
              .existsSync(),
          isFalse,
        );
      },
    );
  });

  group(
    'ReviewLocalServer CRUD, Flutter inspector lines, and custom directory',
    () {
      test('supports full CRUD in default .review_comments with Flutter pre-resolved lines and widget selectors', () async {
        final screenFile = writeRepoFile('lib/screens/checkout_screen.dart', '''
import 'package:flutter/material.dart';

class CheckoutCard extends StatelessWidget {
  const CheckoutCard({super.key});

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: () {},
      child: const Text('Pay now'),
    );
  }
}
''');

        final server = await ReviewLocalServer.start(
          repoRoot: tempRepo.path,
          preferredPort: 0,
        );
        addTearDown(server.close);

        // 1. POST comment with pre-resolved Flutter file:// URI and startLine.
        final createRes = await sendJsonRequest(
          server.port,
          'POST',
          '/api/comments',
          origin: 'http://127.0.0.1:8080',
          body: {
            'pageUrl': '/checkout',
            'pageTitle': 'Checkout',
            'sourceFile': Uri.file(screenFile.path).toString(),
            'startLine': 8,
            'endLine': 11,
            'anchorType': 'element',
            'selector': 'flutter:FilledButton',
            'elementTag': 'FilledButton',
            'elementText': 'Pay now',
            'comment': 'Make button full width on mobile.',
          },
        );
        expect(createRes.status, HttpStatus.created);
        expect(createRes.json['feedbackFile'], '.review_comments/feedback.md');

        final created = (createRes.json['comment'] as Map)
            .cast<String, Object?>();
        final firstId = created['id'] as String;
        expect(created['sourceFile'], 'lib/screens/checkout_screen.dart');
        expect(created['resolvedFile'], 'lib/screens/checkout_screen.dart');
        expect(created['startLine'], 8);
        expect(created['endLine'], 11);
        expect(created['codeSnippet'], contains('return FilledButton('));

        // 2. POST comment resolved via flutter:CheckoutCard selector fallback.
        final widgetRes = await sendJsonRequest(
          server.port,
          'POST',
          '/api/comments',
          body: {
            'pageUrl': '/checkout',
            'anchorType': 'element',
            'selector': 'flutter:CheckoutCard',
            'elementTag': 'CheckoutCard',
            'comment': 'Add elevation border to CheckoutCard.',
          },
        );
        expect(widgetRes.status, HttpStatus.created);
        final widgetComment = (widgetRes.json['comment'] as Map)
            .cast<String, Object?>();
        final secondId = widgetComment['id'] as String;
        expect(
          widgetComment['resolvedFile'],
          'lib/screens/checkout_screen.dart',
        );
        expect(widgetComment['startLine'], 3);

        final feedbackMd = File(
          path.join(tempRepo.path, '.review_comments', 'feedback.md'),
        ).readAsStringSync();
        expect(feedbackMd, contains('- **Open comments**: 2'));
        expect(
          feedbackMd,
          contains('dart run review_comments resolve $firstId'),
        );

        // 3. PATCH -> resolve first comment.
        final patchRes = await sendJsonRequest(
          server.port,
          'PATCH',
          '/api/comments/$firstId',
          body: {'status': 'resolved'},
        );
        expect(patchRes.status, HttpStatus.ok);
        expect(patchRes.json['counts'], {'open': 1, 'resolved': 1, 'total': 2});

        // 4. Bulk DELETE resolved comments, then single DELETE second comment.
        final bulkDelete = await sendJsonRequest(
          server.port,
          'DELETE',
          '/api/comments?status=resolved',
        );
        expect(bulkDelete.status, HttpStatus.ok);
        expect(bulkDelete.json['deleted'], 1);

        final singleDelete = await sendJsonRequest(
          server.port,
          'DELETE',
          '/api/comments/$secondId',
        );
        expect(singleDelete.status, HttpStatus.ok);
        expect(singleDelete.json['counts'], {
          'open': 0,
          'resolved': 0,
          'total': 0,
        });
      });

      test(
        'supports custom .dash_review directory and custom cliResolveCommand',
        () async {
          writeRepoFile('sites/docs/src/content/ui/layout/index.md', '''
## Row and Column

Use [`Row`](/ui/row) and `Column` to position widgets.
''');

          final server = await ReviewLocalServer.start(
            repoRoot: tempRepo.path,
            site: 'docs',
            preferredPort: 0,
            config: ReviewProjectConfig.flutterWebsite(),
          );
          addTearDown(server.close);

          final health = await sendJsonRequest(
            server.port,
            'GET',
            '/api/health',
          );
          expect(health.json['feedbackFile'], '.dash_review/feedback.md');

          final createRes = await sendJsonRequest(
            server.port,
            'POST',
            '/api/comments',
            body: {
              'site': 'docs',
              'pageUrl': '/ui/layout/',
              'sourceFile': 'sites/docs/src/content/ui/layout/index.md',
              'selectedText': 'Use Row and Column to position widgets.',
              'comment': 'Mention Flex as well.',
            },
          );
          expect(createRes.status, HttpStatus.created);
          expect(createRes.json['feedbackFile'], '.dash_review/feedback.md');

          final created = (createRes.json['comment'] as Map)
              .cast<String, Object?>();
          final id = created['id'] as String;

          final feedbackFile = File(
            path.join(tempRepo.path, '.dash_review', 'feedback.md'),
          );
          expect(feedbackFile.existsSync(), isTrue);
          final md = feedbackFile.readAsStringSync();
          expect(md, contains('.dash_review/feedback.md'));
          expect(md, contains('dart run dash_site review resolve $id'));
        },
      );
    },
  );
}
