import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:review_comments/cli.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempRepo;

  setUp(() {
    tempRepo = Directory.systemTemp.createTempSync(
      'review_comments_locator_test_',
    );
  });

  tearDown(() {
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

  group('locateHighlightInRepo — Markdown, YAML, and Jaspr', () {
    test('resolves exact single-line and multi-line matches with snippet', () {
      writeRepoFile('content/ui/layout/index.md', '''
---
title: Layouts in Flutter
---

## Introduction

Flutter layouts are built from widgets.
Compose simple widgets to build complex user interfaces
across mobile, web, and desktop screens.
Always test with multiple screen sizes.
''');

      final single = locateHighlightInRepo(
        repoRoot: tempRepo.path,
        sourceFile: 'content/ui/layout/index.md',
        selectedText: 'Flutter layouts are built from widgets.',
      );

      expect(single.resolvedFile, 'content/ui/layout/index.md');
      expect(single.startLine, 7);
      expect(single.endLine, 7);
      expect(
        single.codeSnippet,
        contains('Flutter layouts are built from widgets.'),
      );

      final multi = locateHighlightInRepo(
        repoRoot: tempRepo.path,
        sourceFile: 'content/ui/layout/index.md',
        selectedText:
            'Compose simple widgets to build complex user interfaces\n'
            'across mobile, web, and desktop screens.',
      );

      expect(multi.resolvedFile, 'content/ui/layout/index.md');
      expect(multi.startLine, 8);
      expect(multi.endLine, 9);
    });

    test('matches rendered prose across Markdown links, inline code, bold, and snake_case', () {
      writeRepoFile('content/row-col.md', '''
---
title: Row and Column
---

To arrange children linearly,
use the [`Row`](/ui/widgets/row) and [`Column`][col-ref] widgets
with **flexible** `Expanded` children and `main_axis_alignment`
or _cross_ axis properties.

[col-ref]: https://api.flutter.dev/flutter/widgets/Column-class.html
''');

      final located = locateHighlightInRepo(
        repoRoot: tempRepo.path,
        sourceFile: 'content/row-col.html',
        selectedText:
            'use the Row and Column widgets with flexible Expanded children '
            'and main_axis_alignment or cross axis properties.',
      );

      expect(located.resolvedFile, 'content/row-col.md');
      expect(located.startLine, 6);
      expect(located.endLine, 8);
      expect(located.codeSnippet, contains('[`Row`](/ui/widgets/row)'));
    });

    test(
      'resolves multi-site Liquid includes, YAML data, and Jaspr components',
      () {
        writeRepoFile('sites/docs/src/content/install/index.md', '''
---
title: Install Flutter
---

{% include 'docs/install/quick.md' %}
''');
        writeRepoFile('sites/docs/src/_includes/docs/install/quick.md', '''
## System requirements

Download the `flutter` archive and add `flutter/bin` to your `PATH`.
''');
        writeRepoFile('sites/docs/src/data/glossary.yml', '''
- term: Impeller
  short_description: Predictable shader compilation runtime for Flutter.
''');
        writeRepoFile('sites/www/content/index.md', '''
---
title: Flutter
---

<HomePage />
''');
        writeRepoFile('sites/www/lib/src/pages/home_page.dart', '''
class HomePage {
  void build() {
    final subtitle =
        'Flutter transforms the development process. '
        'Build, test, and deploy beautiful apps from a single codebase.';
  }
}
''');

        final preset = ReviewProjectConfig.flutterWebsite();

        final fromInclude = locateHighlightInRepo(
          repoRoot: tempRepo.path,
          site: 'docs',
          sourceFile: 'sites/docs/src/content/install/',
          selectedText:
              'Download the flutter archive and add flutter/bin to your PATH.',
          config: preset,
        );
        expect(
          fromInclude.resolvedFile,
          'sites/docs/src/_includes/docs/install/quick.md',
        );
        expect(fromInclude.startLine, 3);

        final fromData = locateHighlightInRepo(
          repoRoot: tempRepo.path,
          site: 'docs',
          sourceFile: 'sites/docs/src/content/install/index.md',
          selectedText: 'Predictable shader compilation runtime for Flutter.',
          config: preset,
        );
        expect(fromData.resolvedFile, 'sites/docs/src/data/glossary.yml');
        expect(fromData.startLine, 2);

        final fromComponent = locateHighlightInRepo(
          repoRoot: tempRepo.path,
          site: 'www',
          sourceFile: 'sites/www/content/index.md',
          selectedText:
              'Flutter transforms the development process. '
              'Build, test, and deploy beautiful apps from a single codebase.',
          config: preset,
        );
        expect(
          fromComponent.resolvedFile,
          'sites/www/lib/src/pages/home_page.dart',
        );
        expect(fromComponent.startLine, 4);
        expect(fromComponent.endLine, 5);
      },
    );

    test('falls back to headingAnchor when text selection is unavailable', () {
      writeRepoFile('content/impeller.md', '''
# Impeller rendering engine

## How shader compilation works

Details here.

### Custom anchor section {#ios-metal-backend}

More details.
''');

      final slugMatch = locateHighlightInRepo(
        repoRoot: tempRepo.path,
        sourceFile: 'content/impeller.md',
        headingAnchor: '#how-shader-compilation-works',
      );
      expect(slugMatch.resolvedFile, 'content/impeller.md');
      expect(slugMatch.startLine, 3);

      final explicitIdMatch = locateHighlightInRepo(
        repoRoot: tempRepo.path,
        sourceFile: 'content/impeller.md',
        headingAnchor: '#ios-metal-backend',
      );
      expect(explicitIdMatch.startLine, 7);
    });
  });

  group(
    'locateHighlightInRepo — Flutter Web widgets, URIs, and inspector lines',
    () {
      test('matches single-quoted, double-quoted, escaped, and multi-line Text widgets in lib/**/*.dart', () {
        writeRepoFile('lib/models/checkout.g.dart', '''
// GENERATED CODE - DO NOT MODIFY BY HAND
const generatedLabel = 'Pay now';
''');
        writeRepoFile('lib/screens/checkout_screen.dart', '''
import 'package:flutter/material.dart';

class CheckoutScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Text('Pay now'),
        const Text("Confirm order"),
        const Text('Don\\'t miss your discount'),
        const Text(
          'Encrypted end-to-end '
          'payment processing.',
        ),
      ],
    );
  }
}
''');

        // Hand-authored Dart file is preferred over *.g.dart generated file!
        final singleQuote = locateHighlightInRepo(
          repoRoot: tempRepo.path,
          selectedText: 'Pay now',
        );
        expect(singleQuote.resolvedFile, 'lib/screens/checkout_screen.dart');
        expect(singleQuote.startLine, 8);

        final doubleQuote = locateHighlightInRepo(
          repoRoot: tempRepo.path,
          selectedText: 'Confirm order',
        );
        expect(doubleQuote.resolvedFile, 'lib/screens/checkout_screen.dart');
        expect(doubleQuote.startLine, 9);

        final escapedQuote = locateHighlightInRepo(
          repoRoot: tempRepo.path,
          selectedText: "Don't miss your discount",
        );
        expect(escapedQuote.resolvedFile, 'lib/screens/checkout_screen.dart');
        expect(escapedQuote.startLine, 10);

        final adjacentMultiLine = locateHighlightInRepo(
          repoRoot: tempRepo.path,
          selectedText: 'Encrypted end-to-end payment processing.',
        );
        expect(
          adjacentMultiLine.resolvedFile,
          'lib/screens/checkout_screen.dart',
        );
        expect(adjacentMultiLine.startLine, 12);
        expect(adjacentMultiLine.endLine, 13);
      });

      test('normalizes file:// and package: URIs and preserves pre-resolved Flutter startLine', () {
        final mainFile = writeRepoFile('lib/screens/checkout_screen.dart', '''
import 'package:flutter/material.dart';

class CheckoutScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: () {},
      child: const Icon(Icons.lock),
    );
  }
}
''');
        writeRepoFile('examples/demo_app/lib/main.dart', '''
void main() {
  runApp(const DemoApp());
}
''');

        final fileUri = Uri.file(mainFile.path).toString();
        expect(
          normalizeSourcePathInput(tempRepo.path, fileUri),
          'lib/screens/checkout_screen.dart',
        );
        expect(
          normalizeSourcePathInput(
            tempRepo.path,
            'package:shop_app/screens/checkout_screen.dart',
          ),
          'lib/screens/checkout_screen.dart',
        );
        expect(
          normalizeSourcePathInput(tempRepo.path, 'package:demo_app/main.dart'),
          'examples/demo_app/lib/main.dart',
        );

        final preResolvedFromFileUri = locateHighlightInRepo(
          repoRoot: tempRepo.path,
          sourceFile: fileUri,
          startLine: 6,
          endLine: 9,
        );
        expect(
          preResolvedFromFileUri.resolvedFile,
          'lib/screens/checkout_screen.dart',
        );
        expect(preResolvedFromFileUri.startLine, 6);
        expect(preResolvedFromFileUri.endLine, 9);
        expect(
          preResolvedFromFileUri.codeSnippet,
          contains('return FilledButton('),
        );

        final preResolvedFromPackageUri = locateHighlightInRepo(
          repoRoot: tempRepo.path,
          sourceFile: 'package:shop_app/screens/checkout_screen.dart',
          startLine: 8,
        );
        expect(
          preResolvedFromPackageUri.resolvedFile,
          'lib/screens/checkout_screen.dart',
        );
        expect(preResolvedFromPackageUri.startLine, 8);
        expect(preResolvedFromPackageUri.endLine, 8);
        expect(
          preResolvedFromPackageUri.codeSnippet,
          contains('const Icon(Icons.lock)'),
        );
      });

      test('falls back to flutter:<WidgetClass> selector declaration in lib/**/*.dart', () {
        writeRepoFile('lib/widgets/checkout_card.dart', '''
import 'package:flutter/material.dart';

class CheckoutCard extends StatelessWidget {
  const CheckoutCard({super.key});

  @override
  Widget build(BuildContext context) => const Card();
}
''');

        final byWidgetSelector = locateHighlightInRepo(
          repoRoot: tempRepo.path,
          selector: "flutter:CheckoutCard[key=[<'summary'>]]",
        );
        expect(byWidgetSelector.resolvedFile, 'lib/widgets/checkout_card.dart');
        expect(byWidgetSelector.startLine, 3);
        expect(
          byWidgetSelector.codeSnippet,
          contains('class CheckoutCard extends StatelessWidget'),
        );
      });

      test('loads review_comments.yaml automatically and skips the review directory itself', () {
        writeRepoFile('review_comments.yaml', '''
review_directory: .custom_reviews
cli_resolve_command: dart run my_tool review resolve
source_roots:
  - app_src
''');
        writeRepoFile('.custom_reviews/feedback.md', '''
Unique phrase inside review artifact
''');
        writeRepoFile('app_src/feature.dart', '''
const label = 'Unique phrase inside review artifact';
''');

        final config = ReviewProjectConfig.load(tempRepo.path);
        expect(config.reviewDirectoryName, '.custom_reviews');
        expect(config.cliResolveCommand, 'dart run my_tool review resolve');
        expect(config.sourceRoots, ['app_src']);

        final located = locateHighlightInRepo(
          repoRoot: tempRepo.path,
          selectedText: 'Unique phrase inside review artifact',
        );
        expect(located.resolvedFile, 'app_src/feature.dart');
        expect(located.startLine, 1);
      });

      test(
        'blocks path traversal, external file:// URIs, and symlink escapes',
        () {
          final outsideDir = Directory.systemTemp.createTempSync(
            'review_comments_outside_',
          );
          addTearDown(() {
            if (outsideDir.existsSync()) {
              outsideDir.deleteSync(recursive: true);
            }
          });

          final secretFile = File(path.join(outsideDir.path, 'secret.dart'))
            ..writeAsStringSync("const secret = 'TOP_SECRET_OUTSIDE_TOKEN';\n");

          final symlink = Link(
            path.join(tempRepo.path, 'lib', 'escaped_secret.dart'),
          )..createSync(secretFile.path, recursive: true);
          expect(symlink.existsSync(), isTrue);

          final traversal = locateHighlightInRepo(
            repoRoot: tempRepo.path,
            sourceFile: '../../${path.basename(outsideDir.path)}/secret.dart',
            startLine: 1,
            selectedText: 'TOP_SECRET_OUTSIDE_TOKEN',
          );
          expect(traversal.resolvedFile, isEmpty);
          expect(traversal.startLine, isNull);
          expect(traversal.codeSnippet, isNull);

          final externalFileUri = locateHighlightInRepo(
            repoRoot: tempRepo.path,
            sourceFile: Uri.file(secretFile.path).toString(),
            startLine: 1,
            selectedText: 'TOP_SECRET_OUTSIDE_TOKEN',
          );
          expect(externalFileUri.resolvedFile, isEmpty);
          expect(externalFileUri.startLine, isNull);
          expect(externalFileUri.codeSnippet, isNull);

          final viaSymlink = locateHighlightInRepo(
            repoRoot: tempRepo.path,
            sourceFile: 'lib/escaped_secret.dart',
            startLine: 1,
            selectedText: 'TOP_SECRET_OUTSIDE_TOKEN',
          );
          expect(viaSymlink.resolvedFile, isEmpty);
          expect(viaSymlink.startLine, isNull);
          expect(viaSymlink.codeSnippet, isNull);

          expect(
            sanitizeRepoRelativePath(tempRepo.path, '../../etc/passwd'),
            isNull,
          );
          expect(
            normalizeSourcePathInput(tempRepo.path, 'file:///etc/passwd'),
            isNull,
          );
          expect(
            normalizeSourcePathInput(tempRepo.path, '/etc/passwd'),
            isNull,
          );
          expect(
            sanitizeRepoRelativePath(tempRepo.path, 'lib/escaped_secret.dart'),
            isNull,
          );
        },
      );
    },
  );
}
