import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as path;

import '../project_config.dart';
import '../review_server.dart';
import '../review_source_locator.dart';
import 'review_command.dart';

/// Builds child process executable and argument list for `review_comments serve -- <cmd...>`,
/// automatically injecting `--dart-define=REVIEW_COMMENTS_MODE=local` and
/// `--dart-define=REVIEW_COMMENTS_SERVER_PORT=<port>` when wrapping `flutter`
/// or `jaspr` dev/build commands.
({String executable, List<String> arguments}) buildWrappedDevCommandArgs(
  List<String> rawCommand, {
  required int serverPort,
  String? site,
}) {
  if (rawCommand.isEmpty) {
    throw ArgumentError.value(rawCommand, 'rawCommand', 'Must not be empty.');
  }

  final executable = rawCommand.first;
  final rawArgs = rawCommand.sublist(1);

  if (!_supportsDartDefines(executable, rawArgs)) {
    return (executable: executable, arguments: rawArgs);
  }

  final hasModeDefine = rawArgs.any(
    (arg) =>
        arg.startsWith('--dart-define=REVIEW_COMMENTS_MODE=') ||
        arg.startsWith('--dart-define=DASH_REVIEW_MODE='),
  );
  final hasPortDefine = rawArgs.any(
    (arg) =>
        arg.startsWith('--dart-define=REVIEW_COMMENTS_SERVER_PORT=') ||
        arg.startsWith('--dart-define=DASH_REVIEW_SERVER_PORT='),
  );
  final hasSiteDefine = rawArgs.any(
    (arg) =>
        arg.startsWith('--dart-define=REVIEW_COMMENTS_SITE=') ||
        arg.startsWith('--dart-define=DASH_REVIEW_SITE='),
  );

  final injectedDefines = <String>[
    if (!hasModeDefine) '--dart-define=REVIEW_COMMENTS_MODE=local',
    if (!hasPortDefine) '--dart-define=REVIEW_COMMENTS_SERVER_PORT=$serverPort',
    if (site != null && site.trim().isNotEmpty && !hasSiteDefine)
      '--dart-define=REVIEW_COMMENTS_SITE=${site.trim()}',
  ];

  if (injectedDefines.isEmpty) {
    return (executable: executable, arguments: rawArgs);
  }

  final dashDashIndex = rawArgs.indexOf('--');
  if (dashDashIndex >= 0) {
    return (
      executable: executable,
      arguments: <String>[
        ...rawArgs.sublist(0, dashDashIndex),
        ...injectedDefines,
        ...rawArgs.sublist(dashDashIndex),
      ],
    );
  }

  return (
    executable: executable,
    arguments: <String>[...rawArgs, ...injectedDefines],
  );
}

bool _supportsDartDefines(String executable, List<String> args) {
  final exeName = path
      .basenameWithoutExtension(executable.replaceAll(r'\', '/'))
      .toLowerCase();

  String? firstSubcommand(List<String> tokens) {
    for (final token in tokens) {
      if (!token.startsWith('-')) return token;
    }
    return null;
  }

  if (exeName == 'flutter') {
    final sub = firstSubcommand(args);
    return const {'run', 'build', 'test', 'drive'}.contains(sub);
  }

  if (exeName == 'jaspr') {
    final sub = firstSubcommand(args);
    return const {'serve', 'build'}.contains(sub);
  }

  if (exeName == 'dart') {
    final joined = args.join(' ');
    if (joined.contains('jaspr_cli:jaspr') || joined.contains('jaspr')) {
      return args.contains('serve') || args.contains('build');
    }
  }

  return false;
}

/// CLI subcommand that starts [ReviewLocalServer] standalone or wraps a child
/// dev server command (`review_comments serve -- flutter run -d chrome`).
final class ReviewServeCommand extends Command<int> {
  static const String _portOption = 'port';
  static const String _dirOption = 'dir';
  static const String _siteOption = 'site';

  final ReviewExecutionContext _context;
  final Future<void>? _stopSignal;

  ReviewServeCommand(this._context, {Future<void>? stopSignal})
    : _stopSignal = stopSignal {
    argParser
      ..addOption(
        _portOption,
        abbr: 'p',
        defaultsTo: '$defaultReviewServerPort',
        valueHelp: 'port',
        help:
            'Preferred loopback port on 127.0.0.1 '
            '(falls back to an ephemeral port if busy).',
      )
      ..addOption(
        _dirOption,
        valueHelp: 'dir',
        help:
            'Repository-relative review directory '
            '(defaults to .review_comments or review_comments.yaml).',
      )
      ..addOption(
        _siteOption,
        valueHelp: 'site',
        help: 'Optional site identifier for multi-site workspaces.',
      );
  }

  @override
  String get name => 'serve';

  @override
  String get description =>
      'Start the local 127.0.0.1 review sync server (standalone or wrapping a '
      'dev command after --).';

  @override
  String get invocation =>
      '${runner!.executableName} serve [--port=4099] [--dir=.review_comments] '
      '[-- <dev command...>]';

  @override
  Future<int> run() async {
    final args = argResults!;
    final rawPort = args.option(_portOption) ?? '$defaultReviewServerPort';
    final preferredPort = int.tryParse(rawPort);
    if (preferredPort == null || preferredPort < 0 || preferredPort > 65535) {
      usageException('Invalid --$_portOption value "$rawPort".');
    }

    final dirOverride = _context.resolveDirectoryOverride(args);
    if (dirOverride != null &&
        sanitizeRepoRelativePath(_context.repoRoot, dirOverride) == null) {
      usageException(
        'Invalid --$_dirOption "$dirOverride": must stay within repository root.',
      );
    }

    final siteFilter = _context.resolveOptionalSiteFilter(args);
    final effectiveConfig = _context.resolveConfig(
      reviewDirectoryOverride: dirOverride,
    );

    final server = await ReviewLocalServer.start(
      repoRoot: _context.repoRoot,
      site: siteFilter,
      preferredPort: preferredPort,
      config: effectiveConfig,
    );

    StreamSubscription<ProcessSignal>? sigintSub;
    StreamSubscription<ProcessSignal>? sigtermSub;

    try {
      final wrappedCommand = args.rest;
      if (wrappedCommand.isEmpty) {
        final dartDefines = <String>[
          '--dart-define=REVIEW_COMMENTS_MODE=local',
          '--dart-define=REVIEW_COMMENTS_SERVER_PORT=${server.port}',
          if (server.site.isNotEmpty)
            '--dart-define=REVIEW_COMMENTS_SITE=${server.site}',
        ].join(' ');

        _context.out
          ..writeln(
            'Review comments server listening on http://localhost:${server.port} '
            '(${server.origin}, syncing to ${server.feedbackRelativePath})',
          )
          ..writeln('Pass these flags to your Flutter Web or Jaspr dev server:')
          ..writeln('  $dartDefines');

        final done = Completer<void>();
        void completeDone() {
          if (!done.isCompleted) done.complete();
        }

        if (_stopSignal != null) {
          unawaited(_stopSignal.whenComplete(completeDone));
        } else {
          sigintSub = ProcessSignal.sigint.watch().listen(
            (_) => completeDone(),
          );
          if (!Platform.isWindows) {
            sigtermSub = ProcessSignal.sigterm.watch().listen(
              (_) => completeDone(),
            );
          }
        }

        await done.future;
        return 0;
      }

      final built = buildWrappedDevCommandArgs(
        wrappedCommand,
        serverPort: server.port,
        site: server.site,
      );

      _context.out.writeln(
        'Review comments server active on http://localhost:${server.port} '
        '(${server.origin}) -> ${server.feedbackRelativePath}',
      );

      final childEnv = <String, String>{
        ...Platform.environment,
        'REVIEW_COMMENTS_MODE': 'local',
        'REVIEW_COMMENTS_SERVER_PORT': '${server.port}',
        'REVIEW_COMMENTS_SERVER_ORIGIN': server.origin,
        if (server.site.isNotEmpty) 'REVIEW_COMMENTS_SITE': server.site,
      };

      final process = await Process.start(
        built.executable,
        built.arguments,
        workingDirectory: _context.repoRoot,
        environment: childEnv,
        runInShell: Platform.isWindows,
        mode: ProcessStartMode.inheritStdio,
      );

      Future<void> forwardSignal(ProcessSignal signal) async {
        await server.close();
        process.kill(signal);
      }

      sigintSub = ProcessSignal.sigint.watch().listen(
        (signal) => unawaited(forwardSignal(signal)),
      );
      if (!Platform.isWindows) {
        sigtermSub = ProcessSignal.sigterm.watch().listen(
          (signal) => unawaited(forwardSignal(signal)),
        );
      }

      return await process.exitCode;
    } finally {
      await sigintSub?.cancel();
      await sigtermSub?.cancel();
      await server.close();
    }
  }
}
