import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as path;
import 'package:review_comments/cli.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempRepo;

  setUp(() {
    tempRepo = Directory.systemTemp.createTempSync('review_comments_cli_test_');
  });

  tearDown(() {
    if (tempRepo.existsSync()) {
      tempRepo.deleteSync(recursive: true);
    }
  });

  ReviewComment sampleComment({
    required String id,
    String site = '',
    required String pageUrl,
    required String resolvedFile,
    required int startLine,
    required String comment,
    String status = 'open',
  }) => ReviewComment(
    id: id,
    site: site,
    pageUrl: pageUrl,
    pageTitle: 'Sample page',
    sourceFile: resolvedFile,
    resolvedFile: resolvedFile,
    startLine: startLine,
    endLine: startLine,
    codeSnippet: 'Sample snippet line',
    anchorType: 'text',
    selectedText: 'Sample highlighted quote',
    prefixContext: '',
    suffixContext: '',
    selector: 'main p',
    elementTag: 'p',
    elementText: 'Sample highlighted quote',
    headingAnchor: '#intro',
    rectPct: null,
    comment: comment,
    author: 'local',
    status: status,
    createdAt: '2026-11-13T05:00:00.000Z',
    updatedAt: '2026-11-13T05:00:00.000Z',
  );

  Future<({int exitCode, String stdout, String stderr})> runStandaloneCli(
    List<String> args, {
    Future<void>? serveStopSignal,
  }) async {
    final out = StringBuffer();
    final err = StringBuffer();
    final runner = ReviewCommentsCliRunner(
      repoRoot: tempRepo.path,
      serveStopSignal: serveStopSignal,
      out: out,
      err: err,
    );
    final code = await runner.run(args) ?? 0;
    return (exitCode: code, stdout: out.toString(), stderr: err.toString());
  }

  group('Standalone review_comments CLI (list, prompt, resolve, clear)', () {
    test('lists, exports prompt, resolves, and clears comments', () async {
      final store = ReviewCommentStore(tempRepo.path);
      store.saveComments([
        sampleComment(
          id: 'rv_101',
          pageUrl: '/checkout',
          resolvedFile: 'lib/screens/checkout_screen.dart',
          startLine: 18,
          comment: 'Clarify button label.',
        ),
        sampleComment(
          id: 'rv_102',
          pageUrl: '/details',
          resolvedFile: 'lib/screens/details_screen.dart',
          startLine: 42,
          comment: 'Already addressed.',
          status: 'resolved',
        ),
      ]);

      final listAll = await runStandaloneCli(['list']);
      expect(listAll.exitCode, 0);
      expect(listAll.stdout, contains('rv_101'));
      expect(listAll.stdout, contains('rv_102'));

      final listOpenJson = await runStandaloneCli([
        'list',
        '--status=open',
        '--json',
      ]);
      expect(listOpenJson.exitCode, 0);
      final parsed = jsonDecode(listOpenJson.stdout) as Map<String, Object?>;
      expect(parsed['ok'], isTrue);
      expect(parsed['feedbackFile'], '.review_comments/feedback.md');
      expect(parsed['comments'] as List<Object?>, hasLength(1));

      final promptRes = await runStandaloneCli(['prompt']);
      expect(promptRes.exitCode, 0);
      expect(promptRes.stdout, contains('rv_101'));
      expect(promptRes.stdout, contains('lib/screens/checkout_screen.dart:18'));
      expect(
        promptRes.stdout,
        contains('dart run review_comments resolve rv_101'),
      );
      expect(promptRes.stdout, isNot(contains('rv_102')));

      final missingRes = await runStandaloneCli(['resolve', 'rv_missing']);
      expect(missingRes.exitCode, 1);
      expect(missingRes.stderr, contains('rv_missing'));

      final resolveOne = await runStandaloneCli(['resolve', 'rv_101']);
      expect(resolveOne.exitCode, 0);
      expect(
        store.loadComments().every((item) => item.status == 'resolved'),
        isTrue,
      );

      final clearResolved = await runStandaloneCli(['clear']);
      expect(clearResolved.exitCode, 0);
      expect(store.loadComments(), isEmpty);
    });

    test(
      'clear and resolve --all do not create .review_comments in a clean workspace',
      () async {
        final reviewDir = Directory(
          path.join(tempRepo.path, '.review_comments'),
        );
        expect(reviewDir.existsSync(), isFalse);

        final resolveAllRes = await runStandaloneCli(['resolve', '--all']);
        expect(resolveAllRes.exitCode, 0);
        expect(reviewDir.existsSync(), isFalse);

        final clearResolvedRes = await runStandaloneCli(['clear']);
        expect(clearResolvedRes.exitCode, 0);
        expect(reviewDir.existsSync(), isFalse);

        final clearAllRes = await runStandaloneCli(['clear', '--all']);
        expect(clearAllRes.exitCode, 0);
        expect(reviewDir.existsSync(), isFalse);
      },
    );
  });

  group('Embedded ReviewCommand mounted in host CommandRunner', () {
    test(
      'supports custom reviewDirectoryName (.dash_review), cliCommandDisplay, and global --site',
      () async {
        final preset = ReviewProjectConfig.flutterWebsite();
        final store = ReviewCommentStore(tempRepo.path, config: preset);
        store.saveComments([
          sampleComment(
            id: 'rv_docs_1',
            site: 'docs',
            pageUrl: '/ui/layout/',
            resolvedFile: 'sites/docs/src/content/ui/layout/index.md',
            startLine: 12,
            comment: 'Docs feedback.',
          ),
          sampleComment(
            id: 'rv_www_1',
            site: 'www',
            pageUrl: '/',
            resolvedFile: 'sites/www/lib/src/pages/home_page.dart',
            startLine: 44,
            comment: 'WWW feedback.',
          ),
        ]);

        Future<({int exitCode, String stdout})> runHost(
          List<String> args,
        ) async {
          final out = StringBuffer();
          final err = StringBuffer();
          final hostRunner =
              CommandRunner<int>('dart run dash_site', 'Host CLI')
                ..argParser.addOption(
                  'site',
                  allowed: const ['docs', 'www'],
                  defaultsTo: 'docs',
                )
                ..addCommand(
                  ReviewCommand(
                    repoRoot: tempRepo.path,
                    config: preset,
                    cliCommandDisplay: 'dart run dash_site review',
                    out: out,
                    err: err,
                  ),
                );
          final code = await hostRunner.run(args) ?? 0;
          return (exitCode: code, stdout: out.toString());
        }

        final unparsedGlobal = await runHost(['review', 'list']);
        expect(unparsedGlobal.exitCode, 0);
        expect(unparsedGlobal.stdout, contains('rv_docs_1'));
        expect(unparsedGlobal.stdout, contains('rv_www_1'));

        final globalWww = await runHost(['--site=www', 'review', 'list']);
        expect(globalWww.exitCode, 0);
        expect(globalWww.stdout, contains('rv_www_1'));
        expect(globalWww.stdout, isNot(contains('rv_docs_1')));

        final promptDocs = await runHost(['review', 'prompt', '--site=docs']);
        expect(promptDocs.exitCode, 0);
        expect(
          promptDocs.stdout,
          contains('dart run dash_site review resolve rv_docs_1'),
        );
      },
    );
  });

  group('review_comments serve & buildWrappedDevCommandArgs', () {
    test('injects --dart-define flags into flutter and jaspr dev commands', () {
      final flutterArgs = buildWrappedDevCommandArgs([
        'flutter',
        'run',
        '-d',
        'chrome',
      ], serverPort: 4099);
      expect(flutterArgs.executable, 'flutter');
      expect(
        flutterArgs.arguments,
        equals([
          'run',
          '-d',
          'chrome',
          '--dart-define=REVIEW_COMMENTS_MODE=local',
          '--dart-define=REVIEW_COMMENTS_SERVER_PORT=4099',
        ]),
      );

      final jasprArgs = buildWrappedDevCommandArgs(
        ['jaspr', 'serve'],
        serverPort: 4123,
        site: 'docs',
      );
      expect(jasprArgs.executable, 'jaspr');
      expect(
        jasprArgs.arguments,
        equals([
          'serve',
          '--dart-define=REVIEW_COMMENTS_MODE=local',
          '--dart-define=REVIEW_COMMENTS_SERVER_PORT=4123',
          '--dart-define=REVIEW_COMMENTS_SITE=docs',
        ]),
      );

      final genericArgs = buildWrappedDevCommandArgs([
        'python3',
        '-m',
        'http.server',
      ], serverPort: 4099);
      expect(genericArgs.executable, 'python3');
      expect(genericArgs.arguments, equals(['-m', 'http.server']));
    });

    test('runs standalone serve cleanly until stopSignal completes', () async {
      final stopCompleter = Completer<void>();
      final futureResult = runStandaloneCli([
        'serve',
        '--port=0',
        '--dir=.custom_review',
      ], serveStopSignal: stopCompleter.future);

      await Future<void>.delayed(const Duration(milliseconds: 80));
      stopCompleter.complete();

      final result = await futureResult;
      expect(result.exitCode, 0);
      expect(result.stdout, contains('http://127.0.0.1:'));
      expect(result.stdout, contains('.custom_review/feedback.md'));
      expect(
        result.stdout,
        contains('--dart-define=REVIEW_COMMENTS_MODE=local'),
      );
      expect(
        result.stdout,
        contains('--dart-define=REVIEW_COMMENTS_SERVER_PORT='),
      );
    });

    test(
      'runs wrapped child process with REVIEW_COMMENTS_SERVER_PORT and closes server on exit',
      () async {
        final probeScript = File(path.join(tempRepo.path, 'probe.dart'))
          ..writeAsStringSync('''
import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  final port = int.parse(Platform.environment['REVIEW_COMMENTS_SERVER_PORT']!);
  final client = HttpClient();
  final req = await client.get('127.0.0.1', port, '/api/health');
  final res = await req.close();
  final body = jsonDecode(await utf8.decoder.bind(res).join()) as Map;
  client.close(force: true);
  if (res.statusCode != 200 || body['ok'] != true) {
    exit(2);
  }
}
''');

        final result = await runStandaloneCli([
          'serve',
          '--port=0',
          '--',
          Platform.resolvedExecutable,
          probeScript.path,
        ]);
        expect(result.exitCode, 0);
        expect(result.stdout, contains('Review comments server active on'));
      },
    );
  });
}
