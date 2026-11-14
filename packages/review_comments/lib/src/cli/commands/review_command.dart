import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';

import '../project_config.dart';
import '../review_server.dart';
import '../review_source_locator.dart';
import 'serve_command.dart';

const String _siteOptionName = 'site';
const String _dirOptionName = 'dir';

/// Shared execution context for review CLI commands, supporting both top-level
/// `review_comments <cmd>` execution and embedded `<host> review <cmd>`
/// subcommands.
final class ReviewExecutionContext {
  final String? _repoRootOverride;
  final ReviewProjectConfig? _baseConfig;
  final String? _reviewDirectoryOverride;
  final String? _cliResolveCommandOverride;
  final List<String>? allowedSites;
  final StringSink out;
  final StringSink err;
  final ArgResults? Function() _parentResults;
  final ArgResults? Function() _globalResults;

  ReviewExecutionContext({
    String? repoRoot,
    ReviewProjectConfig? config,
    String? reviewDirectoryName,
    String? cliResolveCommand,
    this.allowedSites,
    StringSink? out,
    StringSink? err,
    required ArgResults? Function() parentResults,
    required ArgResults? Function() globalResults,
  }) : _repoRootOverride = repoRoot,
       _baseConfig = config,
       _reviewDirectoryOverride = reviewDirectoryName,
       _cliResolveCommandOverride = cliResolveCommand,
       out = out ?? stdout,
       err = err ?? stderr,
       _parentResults = parentResults,
       _globalResults = globalResults;

  String get repoRoot => _repoRootOverride ?? Directory.current.path;

  ReviewProjectConfig resolveConfig({String? reviewDirectoryOverride}) {
    final loaded = _baseConfig ?? ReviewProjectConfig.load(repoRoot);
    return loaded.copyWith(
      reviewDirectoryName: reviewDirectoryOverride ?? _reviewDirectoryOverride,
      cliResolveCommand: _cliResolveCommandOverride,
      allowedSites: allowedSites,
    );
  }

  ReviewCommentStore resolveStore(ArgResults? subcommandArgs) {
    final dirOverride = resolveDirectoryOverride(subcommandArgs);
    if (dirOverride != null &&
        sanitizeRepoRelativePath(repoRoot, dirOverride) == null) {
      throw UsageException(
        'Invalid --$_dirOptionName "$dirOverride": must stay within repository root.',
        '',
      );
    }
    return ReviewCommentStore(
      repoRoot,
      config: resolveConfig(reviewDirectoryOverride: dirOverride),
    );
  }

  String? resolveDirectoryOverride(ArgResults? subcommandArgs) {
    if (subcommandArgs != null &&
        subcommandArgs.options.contains(_dirOptionName) &&
        subcommandArgs.wasParsed(_dirOptionName)) {
      return subcommandArgs.option(_dirOptionName);
    }
    final parent = _parentResults();
    if (parent != null &&
        parent.options.contains(_dirOptionName) &&
        parent.wasParsed(_dirOptionName)) {
      return parent.option(_dirOptionName);
    }
    final global = _globalResults();
    if (global != null &&
        global.options.contains(_dirOptionName) &&
        global.wasParsed(_dirOptionName)) {
      return global.option(_dirOptionName);
    }
    return null;
  }

  String? resolveOptionalSiteFilter(ArgResults? subcommandArgs) {
    if (subcommandArgs != null &&
        subcommandArgs.options.contains(_siteOptionName) &&
        subcommandArgs.wasParsed(_siteOptionName)) {
      return subcommandArgs.option(_siteOptionName);
    }
    final parent = _parentResults();
    if (parent != null &&
        parent.options.contains(_siteOptionName) &&
        parent.wasParsed(_siteOptionName)) {
      return parent.option(_siteOptionName);
    }
    final global = _globalResults();
    if (global != null &&
        global.options.contains(_siteOptionName) &&
        global.wasParsed(_siteOptionName)) {
      return global.option(_siteOptionName);
    }
    return null;
  }
}

void _addSiteOption(ArgParser parser, {List<String>? allowedSites}) {
  parser.addOption(
    _siteOptionName,
    allowed: (allowedSites != null && allowedSites.isNotEmpty)
        ? allowedSites
        : null,
    valueHelp: (allowedSites != null && allowedSites.isNotEmpty)
        ? allowedSites.join('|')
        : 'site',
    help: 'Optional site filter.',
  );
}

/// Reusable `review` command (`Command<int>`) that can be mounted inside any
/// host `CommandRunner` (for example, `dart run dash_site review ...`).
final class ReviewCommand extends Command<int> {
  final String _commandName;
  final String _displayDirectory;
  late final ReviewExecutionContext _context;

  ReviewCommand({
    String name = 'review',
    String? repoRoot,
    ReviewProjectConfig? config,
    String? reviewDirectoryName,
    String? cliCommandDisplay,
    String? cliResolveCommand,
    List<String>? allowedSites,
    bool includeServeSubcommand = false,
    Future<void>? serveStopSignal,
    StringSink? out,
    StringSink? err,
  }) : _commandName = name,
       _displayDirectory =
           reviewDirectoryName ??
           config?.reviewDirectoryName ??
           defaultReviewDirectoryName {
    final resolvedCliCommand =
        cliResolveCommand ??
        (cliCommandDisplay != null
            ? '${cliCommandDisplay.trim()} resolve'
            : config?.cliResolveCommand);
    final effectiveAllowedSites = allowedSites ?? config?.allowedSites;

    _context = ReviewExecutionContext(
      repoRoot: repoRoot,
      config: config,
      reviewDirectoryName: reviewDirectoryName,
      cliResolveCommand: resolvedCliCommand,
      allowedSites: effectiveAllowedSites,
      out: out,
      err: err,
      parentResults: () => argResults,
      globalResults: () => globalResults,
    );

    _addSiteOption(argParser, allowedSites: effectiveAllowedSites);

    if (includeServeSubcommand) {
      addSubcommand(ReviewServeCommand(_context, stopSignal: serveStopSignal));
    }
    addSubcommand(
      ReviewListCommand(_context, allowedSites: effectiveAllowedSites),
    );
    addSubcommand(
      ReviewPromptCommand(_context, allowedSites: effectiveAllowedSites),
    );
    addSubcommand(
      ReviewResolveCommand(
        _context,
        allowedSites: effectiveAllowedSites,
        displayDirectory: _displayDirectory,
      ),
    );
    addSubcommand(
      ReviewClearCommand(
        _context,
        allowedSites: effectiveAllowedSites,
        displayDirectory: _displayDirectory,
      ),
    );
  }

  @override
  String get name => _commandName;

  @override
  String get description =>
      'Manage local visual review comments synced to $_displayDirectory/.';
}

/// Standalone `review_comments` CLI `CommandRunner` exposing `serve`, `list`,
/// `prompt`, `resolve`, and `clear`.
final class ReviewCommentsCliRunner extends CommandRunner<int> {
  late final ReviewExecutionContext _context;

  ReviewCommentsCliRunner({
    String executableName = 'review_comments',
    String? repoRoot,
    ReviewProjectConfig? config,
    String? reviewDirectoryName,
    String? cliResolveCommand,
    Future<void>? serveStopSignal,
    StringSink? out,
    StringSink? err,
  }) : super(
         executableName,
         'Local visual highlight & coding-agent review CLI for Jaspr and '
         'Flutter Web.',
       ) {
    final effectiveAllowedSites = config?.allowedSites;
    final displayDirectory =
        reviewDirectoryName ??
        config?.reviewDirectoryName ??
        defaultReviewDirectoryName;

    argParser
      ..addOption(
        _dirOptionName,
        valueHelp: 'dir',
        help:
            'Repository-relative review directory '
            '(defaults to .review_comments or review_comments.yaml).',
      )
      ..addOption(
        _siteOptionName,
        allowed:
            (effectiveAllowedSites != null && effectiveAllowedSites.isNotEmpty)
            ? effectiveAllowedSites
            : null,
        valueHelp: 'site',
        help: 'Optional site filter.',
      );

    ArgResults? latestTopLevelResults;
    _context = ReviewExecutionContext(
      repoRoot: repoRoot,
      config: config,
      reviewDirectoryName: reviewDirectoryName,
      cliResolveCommand: cliResolveCommand,
      allowedSites: effectiveAllowedSites,
      out: out,
      err: err,
      parentResults: () => null,
      globalResults: () => latestTopLevelResults,
    );

    addCommand(ReviewServeCommand(_context, stopSignal: serveStopSignal));
    addCommand(
      ReviewListCommand(_context, allowedSites: effectiveAllowedSites),
    );
    addCommand(
      ReviewPromptCommand(_context, allowedSites: effectiveAllowedSites),
    );
    addCommand(
      ReviewResolveCommand(
        _context,
        allowedSites: effectiveAllowedSites,
        displayDirectory: displayDirectory,
      ),
    );
    addCommand(
      ReviewClearCommand(
        _context,
        allowedSites: effectiveAllowedSites,
        displayDirectory: displayDirectory,
      ),
    );

    _bindGlobalResultsCapture((results) {
      latestTopLevelResults = results;
    });
  }

  void Function(ArgResults)? _onParsed;

  void _bindGlobalResultsCapture(void Function(ArgResults) callback) {
    _onParsed = callback;
  }

  @override
  ArgResults parse(Iterable<String> args) {
    final parsed = super.parse(args);
    _onParsed?.call(parsed);
    return parsed;
  }
}

/// Lists open, resolved, or all local visual review comments.
final class ReviewListCommand extends Command<int> {
  static const String _statusOption = 'status';
  static const String _jsonFlag = 'json';

  final ReviewExecutionContext _context;

  ReviewListCommand(this._context, {List<String>? allowedSites}) {
    _addSiteOption(argParser, allowedSites: allowedSites);
    argParser
      ..addOption(
        _statusOption,
        allowed: const ['open', 'resolved', 'all'],
        defaultsTo: 'all',
        help: 'Filter comments by status.',
      )
      ..addFlag(
        _jsonFlag,
        defaultsTo: false,
        negatable: false,
        help: 'Print comments as JSON.',
      );
  }

  @override
  String get name => 'list';

  @override
  String get description => 'List local visual review comments.';

  @override
  Future<int> run() async {
    final args = argResults!;
    final statusFilter = args.option(_statusOption) ?? 'all';
    final outputJson = args.flag(_jsonFlag);
    final siteFilter = _context.resolveOptionalSiteFilter(args);
    final store = _context.resolveStore(args);

    final allComments = store.loadComments();
    final siteScoped = [
      for (final item in allComments)
        if (siteFilter == null || item.site == siteFilter) item,
    ];
    final filtered = [
      for (final item in siteScoped)
        if (statusFilter == 'all' || item.status == statusFilter) item,
    ];
    final counts = computeCommentCounts(siteScoped);

    if (outputJson) {
      final payload = {
        'ok': true,
        'comments': [for (final item in filtered) item.toJson()],
        'counts': counts,
        'feedbackFile': store.feedbackRelativePath,
      };
      _context.out.writeln(const JsonEncoder.withIndent('  ').convert(payload));
      return 0;
    }

    _context.out.writeln(
      'Review comments '
      '(open: ${counts['open']}, resolved: ${counts['resolved']}, '
      'total: ${counts['total']})',
    );

    if (filtered.isEmpty) {
      _context.out.writeln('No matching review comments.');
      return 0;
    }

    for (final item in filtered) {
      final statusBadge = item.status == 'resolved' ? 'RESOLVED' : 'OPEN';
      final summary = item.comment.replaceAll(RegExp(r'\s+'), ' ').trim();
      final scopeLabel = item.site.isNotEmpty
          ? '${item.site} ${item.pageUrl}'
          : item.pageUrl;
      _context.out.writeln(
        '[$statusBadge] ${item.id}  ${item.locationLabel}  ($scopeLabel)',
      );
      if (item.selectedText.trim().isNotEmpty) {
        final quote = item.selectedText.replaceAll(RegExp(r'\s+'), ' ').trim();
        _context.out.writeln('  Quote: "$quote"');
      }
      _context.out.writeln('  Note: $summary');
    }

    return 0;
  }
}

/// Prints a structured coding-agent prompt containing open visual review
/// comments.
final class ReviewPromptCommand extends Command<int> {
  final ReviewExecutionContext _context;

  ReviewPromptCommand(this._context, {List<String>? allowedSites}) {
    _addSiteOption(argParser, allowedSites: allowedSites);
  }

  @override
  String get name => 'prompt';

  @override
  String get description =>
      'Print a structured coding-agent prompt for open review comments.';

  @override
  Future<int> run() async {
    final siteFilter = _context.resolveOptionalSiteFilter(argResults);
    final store = _context.resolveStore(argResults);
    final comments = store.loadComments();
    final prompt = store.renderAgentPrompt(comments, siteFilter: siteFilter);
    _context.out.write(prompt);
    return 0;
  }
}

/// Marks one or more review comments (or `--all`) resolved and updates
/// `feedback.md`.
final class ReviewResolveCommand extends Command<int> {
  static const String _allFlag = 'all';

  final ReviewExecutionContext _context;
  final String _displayDirectory;

  ReviewResolveCommand(
    this._context, {
    List<String>? allowedSites,
    String displayDirectory = defaultReviewDirectoryName,
  }) : _displayDirectory = displayDirectory {
    _addSiteOption(argParser, allowedSites: allowedSites);
    argParser.addFlag(
      _allFlag,
      defaultsTo: false,
      negatable: false,
      help: 'Mark all open comments as resolved.',
    );
  }

  @override
  String get name => 'resolve';

  @override
  String get description =>
      'Mark a comment <id> (or --all) resolved and sync '
      '$_displayDirectory/feedback.md.';

  @override
  String get invocation {
    final prefix = parent != null
        ? '${runner!.executableName} ${parent!.name}'
        : runner!.executableName;
    return '$prefix resolve [<id>...]';
  }

  @override
  Future<int> run() async {
    final args = argResults!;
    final resolveAll = args.flag(_allFlag);
    final targetIds = [
      for (final restArg in args.rest)
        if (restArg.trim().isNotEmpty) restArg.trim(),
    ];

    if (!resolveAll && targetIds.isEmpty) {
      usageException('Specify at least one comment <id> or pass --all.');
    }

    final siteFilter = _context.resolveOptionalSiteFilter(args);
    final store = _context.resolveStore(args);
    final comments = store.loadComments();
    final now = DateTime.now().toUtc();
    final nowIso = now.toIso8601String();

    if (resolveAll) {
      var updatedCount = 0;
      for (var i = 0; i < comments.length; i++) {
        final item = comments[i];
        if (siteFilter != null && item.site != siteFilter) continue;
        if (item.status != 'resolved') {
          comments[i] = item.copyWith(status: 'resolved', updatedAt: nowIso);
          updatedCount++;
        }
      }
      if (comments.isNotEmpty ||
          Directory(store.reviewDirectoryPath).existsSync()) {
        store.saveComments(comments, now: now);
      }
      final counts = computeCommentCounts(comments);
      _context.out.writeln(
        'Resolved $updatedCount comment${updatedCount == 1 ? '' : 's'}. '
        'Remaining open: ${counts['open']}.',
      );
      return 0;
    }

    final missingIds = <String>[];
    var resolvedCount = 0;
    for (final targetId in targetIds) {
      final idx = comments.indexWhere((item) => item.id == targetId);
      if (idx < 0) {
        missingIds.add(targetId);
        continue;
      }
      if (comments[idx].status != 'resolved') {
        comments[idx] = comments[idx].copyWith(
          status: 'resolved',
          updatedAt: nowIso,
        );
      }
      resolvedCount++;
    }

    if (missingIds.isNotEmpty) {
      _context.err.writeln(
        'Error: Comment ID not found: ${missingIds.join(', ')}.',
      );
      if (resolvedCount == 0) {
        return 1;
      }
    }

    store.saveComments(comments, now: now);
    final counts = computeCommentCounts(comments);
    _context.out.writeln(
      'Resolved $resolvedCount comment${resolvedCount == 1 ? '' : 's'}. '
      'Remaining open: ${counts['open']}.',
    );
    return missingIds.isEmpty ? 0 : 1;
  }
}

/// Removes resolved (or `--all`) review comments from the store without
/// creating a review directory in a clean workspace.
final class ReviewClearCommand extends Command<int> {
  static const String _resolvedFlag = 'resolved';
  static const String _allFlag = 'all';

  final ReviewExecutionContext _context;
  final String _displayDirectory;

  ReviewClearCommand(
    this._context, {
    List<String>? allowedSites,
    String displayDirectory = defaultReviewDirectoryName,
  }) : _displayDirectory = displayDirectory {
    _addSiteOption(argParser, allowedSites: allowedSites);
    argParser
      ..addFlag(
        _resolvedFlag,
        defaultsTo: true,
        negatable: false,
        help: 'Remove resolved comments (default).',
      )
      ..addFlag(
        _allFlag,
        defaultsTo: false,
        negatable: false,
        help: 'Remove all comments (both open and resolved).',
      );
  }

  @override
  String get name => 'clear';

  @override
  String get description =>
      'Remove resolved review comments (or --all) from $_displayDirectory/.';

  @override
  Future<int> run() async {
    final args = argResults!;
    final clearAll = args.flag(_allFlag);
    final siteFilter = _context.resolveOptionalSiteFilter(args);

    final store = _context.resolveStore(args);
    final comments = store.loadComments();
    final beforeCount = comments.length;

    comments.removeWhere((item) {
      if (siteFilter != null && item.site != siteFilter) return false;
      if (clearAll) return true;
      return item.status == 'resolved';
    });

    final removedCount = beforeCount - comments.length;
    if (comments.isNotEmpty ||
        Directory(store.reviewDirectoryPath).existsSync()) {
      store.saveComments(comments);
    }
    final counts = computeCommentCounts(comments);
    _context.out.writeln(
      'Cleared $removedCount comment${removedCount == 1 ? '' : 's'}. '
      'Remaining open: ${counts['open']}, resolved: ${counts['resolved']}.',
    );
    return 0;
  }
}
