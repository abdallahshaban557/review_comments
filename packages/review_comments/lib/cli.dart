// Copyright (c) 2026, Abdallah Shaban. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Local `127.0.0.1` review sync HTTP server, multi-framework source-line
/// locator, and embeddable CLI commands for coding-agent feedback workflows.
library;

import 'dart:io';

import 'package:args/command_runner.dart';

import 'src/cli/commands/review_command.dart';

export 'src/cli/commands/review_command.dart'
    show
        ReviewClearCommand,
        ReviewCommand,
        ReviewCommentsCliRunner,
        ReviewExecutionContext,
        ReviewListCommand,
        ReviewPromptCommand,
        ReviewResolveCommand;
export 'src/cli/commands/serve_command.dart'
    show ReviewServeCommand, buildWrappedDevCommandArgs;
export 'src/cli/project_config.dart'
    show
        ReviewProjectConfig,
        ReviewSiteConfig,
        defaultAutoSourceRoots,
        defaultCliResolveCommand,
        defaultReviewConfigFileName,
        defaultReviewDirectoryName,
        defaultReviewServerPort;
export 'src/cli/review_server.dart'
    show
        ReviewComment,
        ReviewCommentStore,
        ReviewLocalServer,
        ReviewStore,
        computeCommentCounts,
        normalizeReviewPageUrl;
export 'src/cli/review_source_locator.dart'
    show
        SourceLocationResult,
        extractCodeSnippet,
        locateHighlightInRepo,
        normalizeSourcePathInput,
        sanitizeRepoRelativePath;

/// Runs the `review_comments` command-line interface and exits with the
/// resulting status code.
Future<Never> runReviewCommentsCli(List<String> arguments) async {
  final runner = ReviewCommentsCliRunner();
  try {
    final code = await runner.run(arguments) ?? 0;
    exit(code);
  } on UsageException catch (error) {
    stderr.writeln(error);
    exit(64);
  }
}
