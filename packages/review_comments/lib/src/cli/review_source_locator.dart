import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as path;

import 'project_config.dart';

/// Resolved repository file path, 1-based line range, and surrounding snippet
/// for a highlighted selection, widget, or element on a rendered page.
typedef SourceLocationResult = ({
  String resolvedFile,
  int? startLine,
  int? endLine,
  String? codeSnippet,
});

const Set<String> _searchableExtensions = {
  '.md',
  '.markdown',
  '.html',
  '.liquid',
  '.yaml',
  '.yml',
  '.json',
  '.dart',
};

const Set<String> _dataExtensions = {'.yaml', '.yml', '.json'};

const Set<String> _defaultSkippedDirectoryNames = {
  '.dart_tool',
  '.dash_review',
  '.firebase',
  '.git',
  '.idea',
  '.review_comments',
  '.vscode',
  '_site',
  'build',
  'node_modules',
};

const Set<String> _frameworkPackageNames = {
  'dart',
  'flutter',
  'flutter_driver',
  'flutter_localizations',
  'flutter_test',
  'flutter_web_plugins',
  'jaspr',
  'jaspr_content',
  'jaspr_router',
  'meta',
  'sky_engine',
  'web',
};

const Set<String> _genericFlutterWrapperTypes = {
  'Align',
  'Builder',
  'Center',
  'Column',
  'ConstrainedBox',
  'Container',
  'Directionality',
  'Expanded',
  'Flexible',
  'Focus',
  'GestureDetector',
  'KeyedSubtree',
  'LayoutBuilder',
  'Listener',
  'Material',
  'MediaQuery',
  'MouseRegion',
  'Padding',
  'Positioned',
  'RepaintBoundary',
  'Row',
  'SafeArea',
  'Semantics',
  'SizedBox',
  'Stack',
  'StatefulWidget',
  'StatelessWidget',
  'Theme',
  'Widget',
};

const int _maxSearchableFileBytes = 2 * 1024 * 1024;

/// Resolves a highlighted text quote, Flutter widget inspector location,
/// element text, heading anchor, or `flutter:<WidgetClass>` selector back to
/// its repository-relative source file and 1-based line range.
///
/// All candidate paths are canonicalized and verified to stay strictly within
/// [repoRoot] so untrusted inputs cannot traverse or symlink-escape outside the
/// repository.
SourceLocationResult locateHighlightInRepo({
  required String repoRoot,
  String site = '',
  String? sourceFile,
  int? startLine,
  int? endLine,
  String? selectedText,
  String? elementText,
  String? headingAnchor,
  String? selector,
  String? pageUrl,
  ReviewProjectConfig? config,
}) {
  final canonicalRoot = _canonicalizeRepoRoot(repoRoot);
  final effectiveConfig = config ?? ReviewProjectConfig.load(canonicalRoot);
  final skippedDirs = <String>{
    ..._defaultSkippedDirectoryNames,
    path.posix
        .split(effectiveConfig.safeReviewDirectoryRelativePath(canonicalRoot))
        .first,
  };

  final normalizedInput = _normalizeSourceInputDetailed(
    canonicalRoot: canonicalRoot,
    rawPath: sourceFile,
  );
  final safeSourceFile = normalizedInput.relPath ?? '';

  // 0. If the client (e.g. Flutter Widget Inspector) already supplied a valid
  //    repo-confined sourceFile and positive 1-based startLine, verify the file
  //    exists inside repoRoot, read its surrounding 3-line snippet, and
  //    preserve resolvedFile + startLine + endLine directly.
  if (startLine != null && startLine > 0 && safeSourceFile.isNotEmpty) {
    final preResolvedFile = _resolveExistingRepoFile(
      canonicalRoot,
      safeSourceFile,
    );
    if (preResolvedFile != null) {
      final content = _readTextFileSafely(preResolvedFile.absPath);
      if (content != null) {
        final lines = content.split('\n');
        if (startLine <= lines.length) {
          final effectiveEnd = (endLine != null && endLine >= startLine)
              ? math.min(endLine, lines.length)
              : startLine;
          return (
            resolvedFile: preResolvedFile.relPath,
            startLine: startLine,
            endLine: effectiveEnd,
            codeSnippet: extractCodeSnippet(lines, startLine, effectiveEnd),
          );
        }
      }
    }
  }

  final primaryCandidates = _collectPrimaryCandidates(
    canonicalRoot: canonicalRoot,
    site: site,
    config: effectiveConfig,
    rawSourceFile: sourceFile,
    safeSourceFile: safeSourceFile,
    pageUrl: pageUrl,
  );

  final queries = <String>[
    if (selectedText != null && selectedText.trim().isNotEmpty)
      selectedText.trim(),
    if (elementText != null &&
        elementText.trim().isNotEmpty &&
        elementText.trim() != selectedText?.trim())
      elementText.trim(),
  ];

  // 1. Search primary candidate file(s) with exact, tolerant, then composite
  //    multi-line matching.
  for (final candidate in primaryCandidates) {
    final content = _readTextFileSafely(candidate.absPath);
    if (content == null) continue;
    final isDart = candidate.relPath.endsWith('.dart');

    for (final query in queries) {
      final exact = _findExactMatch(content, query);
      if (exact != null) {
        return (
          resolvedFile: candidate.relPath,
          startLine: exact.startLine,
          endLine: exact.endLine,
          codeSnippet: exact.codeSnippet,
        );
      }

      final tolerant = _findTolerantMatch(content, query, isDartSource: isDart);
      if (tolerant != null) {
        return (
          resolvedFile: candidate.relPath,
          startLine: tolerant.startLine,
          endLine: tolerant.endLine,
          codeSnippet: tolerant.codeSnippet,
        );
      }

      final composite = _findCompositeMultiLineMatch(
        content,
        query,
        isDartSource: isDart,
      );
      if (composite != null) {
        return (
          resolvedFile: candidate.relPath,
          startLine: composite.startLine,
          endLine: composite.endLine,
          codeSnippet: composite.codeSnippet,
        );
      }
    }
  }

  List<_CandidateFile>? secondaryCandidatesCache;
  List<_CandidateFile> getSecondaryCandidates() =>
      secondaryCandidatesCache ??= _collectSecondaryCandidates(
        canonicalRoot: canonicalRoot,
        site: site,
        config: effectiveConfig,
        primaryCandidates: primaryCandidates,
        skippedDirs: skippedDirs,
      );

  final cachedContents = <String, String>{};
  String? readCached(_CandidateFile candidate) {
    if (cachedContents.containsKey(candidate.relPath)) {
      return cachedContents[candidate.relPath];
    }
    final loaded = _readTextFileSafely(candidate.absPath);
    if (loaded != null) {
      cachedContents[candidate.relPath] = loaded;
    }
    return loaded;
  }

  // 2. Search secondary project sources (delegated components, includes, data,
  //    and configured/auto-discovered sourceRoots such as lib/**/*.dart).
  if (queries.isNotEmpty) {
    final secondaryCandidates = getSecondaryCandidates();

    // Pass A: Exact substring match across secondary sources.
    for (final candidate in secondaryCandidates) {
      final content = readCached(candidate);
      if (content == null) continue;

      for (final query in queries) {
        final exact = _findExactMatch(content, query);
        if (exact != null) {
          return (
            resolvedFile: candidate.relPath,
            startLine: exact.startLine,
            endLine: exact.endLine,
            codeSnippet: exact.codeSnippet,
          );
        }
      }
    }

    // Pass B: Markdown / Dart-string-literal / whitespace-tolerant match across
    // secondary sources.
    for (final candidate in secondaryCandidates) {
      final content = readCached(candidate);
      if (content == null) continue;
      final isDart = candidate.relPath.endsWith('.dart');

      for (final query in queries) {
        final tolerant = _findTolerantMatch(
          content,
          query,
          isDartSource: isDart,
        );
        if (tolerant != null) {
          return (
            resolvedFile: candidate.relPath,
            startLine: tolerant.startLine,
            endLine: tolerant.endLine,
            codeSnippet: tolerant.codeSnippet,
          );
        }
      }
    }

    // Pass C: Multi-line composite subtree text (e.g. Card/ListTile with
    // multiple Text widgets on nearby lines).
    for (final candidate in secondaryCandidates) {
      final content = readCached(candidate);
      if (content == null) continue;
      final isDart = candidate.relPath.endsWith('.dart');

      for (final query in queries) {
        final composite = _findCompositeMultiLineMatch(
          content,
          query,
          isDartSource: isDart,
        );
        if (composite != null) {
          return (
            resolvedFile: candidate.relPath,
            startLine: composite.startLine,
            endLine: composite.endLine,
            codeSnippet: composite.codeSnippet,
          );
        }
      }
    }
  }

  // 3. Fallback to heading anchor (#slug -> matching heading or {#slug}).
  final cleanAnchor = _normalizeHeadingSlug(headingAnchor);
  if (cleanAnchor != null) {
    final anchorCandidates = <_CandidateFile>[
      ...primaryCandidates,
      ..._collectDelegatedPrimaryHints(
        canonicalRoot: canonicalRoot,
        site: site,
        config: effectiveConfig,
        primaryCandidates: primaryCandidates,
        skippedDirs: skippedDirs,
      ),
      if (primaryCandidates.isEmpty) ...getSecondaryCandidates(),
    ];
    final seenPaths = <String>{};
    for (final candidate in anchorCandidates) {
      if (!seenPaths.add(candidate.relPath)) continue;
      final content = readCached(candidate);
      if (content == null) continue;
      final headingMatch = _findHeadingAnchorMatch(content, cleanAnchor);
      if (headingMatch != null) {
        return (
          resolvedFile: candidate.relPath,
          startLine: headingMatch.startLine,
          endLine: headingMatch.endLine,
          codeSnippet: headingMatch.codeSnippet,
        );
      }
    }
  }

  // 4. Fallback to Flutter widget class name (selector: "flutter:CheckoutCard"
  //    -> `class CheckoutCard` in lib/**/*.dart).
  final flutterWidgetName = _extractFlutterSelectorWidgetName(selector);
  if (flutterWidgetName != null) {
    final dartCandidates = <_CandidateFile>[];
    final seenDart = <String>{};
    for (final candidate in [
      ...primaryCandidates,
      ...getSecondaryCandidates(),
    ]) {
      if (candidate.relPath.endsWith('.dart') &&
          seenDart.add(candidate.relPath)) {
        dartCandidates.add(candidate);
      }
    }

    // Pass 4a: Exact widget class/mixin/extension-type declaration.
    for (final candidate in dartCandidates) {
      final content = readCached(candidate);
      if (content == null) continue;
      final declMatch = _findDartWidgetDeclarationMatch(
        content,
        flutterWidgetName,
      );
      if (declMatch != null) {
        return (
          resolvedFile: candidate.relPath,
          startLine: declMatch.startLine,
          endLine: declMatch.endLine,
          codeSnippet: declMatch.codeSnippet,
        );
      }
    }

    // Pass 4b: Widget constructor usage when not a generic layout wrapper.
    if (!_genericFlutterWrapperTypes.contains(flutterWidgetName)) {
      for (final candidate in dartCandidates) {
        final content = readCached(candidate);
        if (content == null) continue;
        final ctorMatch = _findDartWidgetConstructorMatch(
          content,
          flutterWidgetName,
        );
        if (ctorMatch != null) {
          return (
            resolvedFile: candidate.relPath,
            startLine: ctorMatch.startLine,
            endLine: ctorMatch.endLine,
            codeSnippet: ctorMatch.codeSnippet,
          );
        }
      }
    }
  }

  final fallbackResolved = primaryCandidates.isNotEmpty
      ? primaryCandidates.first.relPath
      : (normalizedInput.fromUriScheme ? '' : safeSourceFile);

  return (
    resolvedFile: fallbackResolved,
    startLine: null,
    endLine: null,
    codeSnippet: null,
  );
}

/// Normalizes a raw `sourceFile` path—including `file://` URIs inside
/// [repoRoot], `package:<pkg>/<path>` URIs, `org-dartlang-app:///` URIs, or
/// repository-relative paths—into a clean POSIX path strictly confined within
/// [repoRoot].
///
/// Returns `null` if [rawPath] is empty or attempts to escape [repoRoot].
String? normalizeSourcePathInput(
  String repoRoot,
  String? rawPath, {
  String? canonicalRoot,
}) => _normalizeSourceInputDetailed(
  canonicalRoot: canonicalRoot ?? _canonicalizeRepoRoot(repoRoot),
  rawPath: rawPath,
).relPath;

({String? relPath, bool fromUriScheme}) _normalizeSourceInputDetailed({
  required String canonicalRoot,
  required String? rawPath,
}) {
  if (rawPath == null || rawPath.contains('\x00')) {
    return (relPath: null, fromUriScheme: false);
  }

  var trimmed = rawPath.trim();
  if (trimmed.isEmpty) {
    return (relPath: null, fromUriScheme: false);
  }

  final lower = trimmed.toLowerCase();

  // 1. file:// URI -> must resolve strictly inside canonicalRoot.
  if (lower.startsWith('file://')) {
    final strippedUri = _stripQueryAndFragment(trimmed);
    final uri = Uri.tryParse(strippedUri);
    if (uri == null || uri.scheme.toLowerCase() != 'file') {
      return (relPath: null, fromUriScheme: true);
    }
    final String filePath;
    try {
      filePath = uri.toFilePath();
    } on Object {
      return (relPath: null, fromUriScheme: true);
    }
    return (
      relPath: _confineAbsolutePathToRoot(canonicalRoot, filePath),
      fromUriScheme: true,
    );
  }

  // 2. org-dartlang-app:/// URI emitted by Flutter Web DDC debug builds.
  if (lower.startsWith('org-dartlang-app:')) {
    final strippedUri = _stripQueryAndFragment(trimmed);
    final uri = Uri.tryParse(strippedUri);
    if (uri == null) return (relPath: null, fromUriScheme: true);
    var uriPath = uri.path;
    while (uriPath.startsWith('/')) {
      uriPath = uriPath.substring(1);
    }
    if (uriPath.startsWith('packages/')) {
      final afterPackages = uriPath.substring('packages/'.length);
      final slashIdx = afterPackages.indexOf('/');
      if (slashIdx > 0) {
        final pkgName = afterPackages.substring(0, slashIdx);
        final rest = afterPackages.substring(slashIdx + 1);
        return (
          relPath: _resolvePackageRelativePath(canonicalRoot, pkgName, rest),
          fromUriScheme: true,
        );
      }
    }
    final direct = sanitizeRepoRelativePath(
      canonicalRoot,
      uriPath,
      canonicalRoot: canonicalRoot,
    );
    if (direct != null &&
        _resolveExistingRepoFile(canonicalRoot, direct) != null) {
      return (relPath: direct, fromUriScheme: true);
    }
    final underLib = sanitizeRepoRelativePath(
      canonicalRoot,
      'lib/$uriPath',
      canonicalRoot: canonicalRoot,
    );
    return (relPath: underLib ?? direct, fromUriScheme: true);
  }

  // 3. package:<pkg>/<path> URI -> normalize to lib/<path> (or matching
  //    monorepo package directory inside canonicalRoot).
  if (lower.startsWith('package:')) {
    final withoutScheme = _stripQueryAndFragment(
      trimmed.substring('package:'.length),
    );
    final slashIdx = withoutScheme.indexOf('/');
    if (slashIdx <= 0 || slashIdx == withoutScheme.length - 1) {
      return (relPath: null, fromUriScheme: true);
    }
    final pkgName = withoutScheme.substring(0, slashIdx).trim();
    final rest = withoutScheme.substring(slashIdx + 1).trim();
    if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(pkgName) || rest.isEmpty) {
      return (relPath: null, fromUriScheme: true);
    }
    return (
      relPath: _resolvePackageRelativePath(canonicalRoot, pkgName, rest),
      fromUriScheme: true,
    );
  }

  // 4. Reject other external URI schemes (https://, http://, data:, etc.).
  if (RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(trimmed)) {
    return (relPath: null, fromUriScheme: true);
  }

  // 5. Absolute filesystem path inside canonicalRoot (e.g. /path/to/repo/lib/main.dart).
  final normalizedSlashes = _stripQueryAndFragment(
    trimmed.replaceAll(r'\', '/'),
  );
  if (normalizedSlashes.startsWith('/')) {
    final confinedAbs = _confineAbsolutePathToRoot(
      canonicalRoot,
      normalizedSlashes,
    );
    if (confinedAbs != null) {
      return (relPath: confinedAbs, fromUriScheme: false);
    }
    // Allow web root-relative paths like `/lib/main.dart` or `/sites/docs/...`
    // ONLY when their top-level segment actually exists inside canonicalRoot.
    var strippedLeading = normalizedSlashes;
    while (strippedLeading.startsWith('/')) {
      strippedLeading = strippedLeading.substring(1);
    }
    final firstSeg = strippedLeading.split('/').first;
    if (firstSeg.isEmpty || firstSeg == '.' || firstSeg == '..') {
      return (relPath: null, fromUriScheme: false);
    }
    final topEntity = FileSystemEntity.typeSync(
      path.join(canonicalRoot, firstSeg),
      followLinks: false,
    );
    if (topEntity == FileSystemEntityType.notFound) {
      return (relPath: null, fromUriScheme: true);
    }
  }

  return (
    relPath: sanitizeRepoRelativePath(
      canonicalRoot,
      trimmed,
      canonicalRoot: canonicalRoot,
    ),
    fromUriScheme: false,
  );
}

String? _resolvePackageRelativePath(
  String canonicalRoot,
  String pkgName,
  String restPath,
) {
  final rootLibRel = sanitizeRepoRelativePath(
    canonicalRoot,
    'lib/$restPath',
    canonicalRoot: canonicalRoot,
  );
  if (rootLibRel != null &&
      _resolveExistingRepoFile(canonicalRoot, rootLibRel) != null) {
    return rootLibRel;
  }

  // Check common workspace/monorepo package roots inside canonicalRoot.
  for (final container in const ['packages', 'examples', 'apps', 'sites']) {
    final subPkgRel = sanitizeRepoRelativePath(
      canonicalRoot,
      '$container/$pkgName/lib/$restPath',
      canonicalRoot: canonicalRoot,
    );
    if (subPkgRel != null &&
        _resolveExistingRepoFile(canonicalRoot, subPkgRel) != null) {
      return subPkgRel;
    }
  }

  for (final container in const ['packages', 'examples', 'apps', 'sites']) {
    final subPkgDir = Directory(path.join(canonicalRoot, container, pkgName));
    if (subPkgDir.existsSync()) {
      final subPkgRel = sanitizeRepoRelativePath(
        canonicalRoot,
        '$container/$pkgName/lib/$restPath',
        canonicalRoot: canonicalRoot,
      );
      if (subPkgRel != null) return subPkgRel;
    }
  }

  if (_frameworkPackageNames.contains(pkgName)) {
    return null;
  }

  return rootLibRel;
}

String? _confineAbsolutePathToRoot(String canonicalRoot, String absFilePath) {
  String candidate;
  final file = File(absFilePath);
  if (file.existsSync()) {
    try {
      candidate = path.canonicalize(file.resolveSymbolicLinksSync());
    } on FileSystemException {
      return null;
    }
  } else {
    candidate = path.canonicalize(absFilePath);
  }

  if (!path.isWithin(canonicalRoot, candidate)) {
    return null;
  }
  if (!_verifySymlinksStayWithinRoot(canonicalRoot, candidate)) {
    return null;
  }

  final relative = path.relative(candidate, from: canonicalRoot);
  if (relative.isEmpty || relative == '.' || relative.startsWith('..')) {
    return null;
  }
  return path.posix.joinAll(path.split(relative));
}

String _stripQueryAndFragment(String input) {
  var cleaned = input;
  final queryIdx = cleaned.indexOf('?');
  if (queryIdx >= 0) cleaned = cleaned.substring(0, queryIdx);
  final hashIdx = cleaned.indexOf('#');
  if (hashIdx >= 0) cleaned = cleaned.substring(0, hashIdx);
  return cleaned;
}

/// Canonicalizes [rawPath] relative to [repoRoot] and verifies it stays
/// strictly inside [repoRoot] (including resolving symlinks along its path).
///
/// Returns a normalized POSIX repository-relative path, or `null` if [rawPath]
/// is empty or attempts to escape [repoRoot].
String? sanitizeRepoRelativePath(
  String repoRoot,
  String? rawPath, {
  String? canonicalRoot,
}) {
  if (rawPath == null) return null;
  if (rawPath.contains('\x00')) return null;

  var cleaned = _stripQueryAndFragment(rawPath.trim().replaceAll(r'\', '/'));

  while (cleaned.startsWith('/')) {
    cleaned = cleaned.substring(1);
  }
  if (cleaned.isEmpty || cleaned == '.') return null;

  final root = canonicalRoot ?? _canonicalizeRepoRoot(repoRoot);
  final joined = path.join(root, path.fromUri(Uri(path: cleaned)));
  final canonicalCandidate = path.canonicalize(joined);

  if (!path.isWithin(root, canonicalCandidate)) {
    return null;
  }

  if (!_verifySymlinksStayWithinRoot(root, canonicalCandidate)) {
    return null;
  }

  final relative = path.relative(canonicalCandidate, from: root);
  if (relative.isEmpty || relative == '.' || relative.startsWith('..')) {
    return null;
  }
  return path.posix.joinAll(path.split(relative));
}

String _canonicalizeRepoRoot(String repoRoot) {
  final dir = Directory(repoRoot);
  if (dir.existsSync()) {
    try {
      return path.canonicalize(dir.resolveSymbolicLinksSync());
    } on FileSystemException {
      return path.canonicalize(repoRoot);
    }
  }
  return path.canonicalize(repoRoot);
}

bool _verifySymlinksStayWithinRoot(String canonicalRoot, String targetPath) {
  var current = targetPath;
  while (true) {
    final entityType = FileSystemEntity.typeSync(current, followLinks: false);
    if (entityType != FileSystemEntityType.notFound) {
      try {
        final String resolved;
        if (File(current).existsSync()) {
          resolved = path.canonicalize(
            File(current).resolveSymbolicLinksSync(),
          );
        } else if (Directory(current).existsSync()) {
          resolved = path.canonicalize(
            Directory(current).resolveSymbolicLinksSync(),
          );
        } else {
          if (entityType == FileSystemEntityType.link) return false;
          resolved = path.canonicalize(current);
        }
        if (resolved != canonicalRoot &&
            !path.isWithin(canonicalRoot, resolved)) {
          return false;
        }
      } on FileSystemException {
        return false;
      }
      break;
    }

    final parent = path.dirname(current);
    if (parent == current || parent == canonicalRoot) {
      break;
    }
    current = parent;
  }
  return true;
}

typedef _CandidateFile = ({String relPath, String absPath});

typedef _LineMatch = ({int startLine, int endLine, String codeSnippet});

_CandidateFile? _resolveExistingRepoFile(
  String canonicalRoot,
  String candidateRelativePath,
) {
  final safeRel = sanitizeRepoRelativePath(
    canonicalRoot,
    candidateRelativePath,
    canonicalRoot: canonicalRoot,
  );
  if (safeRel == null) return null;

  final absPath = path.joinAll([canonicalRoot, ...path.posix.split(safeRel)]);
  final file = File(absPath);
  if (!file.existsSync()) return null;

  try {
    final resolvedReal = path.canonicalize(file.resolveSymbolicLinksSync());
    if (!path.isWithin(canonicalRoot, resolvedReal)) {
      return null;
    }
    return (relPath: safeRel, absPath: resolvedReal);
  } on FileSystemException {
    return null;
  }
}

List<String> _resolveContentRoots({
  required String canonicalRoot,
  required String site,
  required ReviewProjectConfig config,
}) {
  final siteCfg = site.isNotEmpty ? config.sites[site] : null;
  if (siteCfg?.contentRoot case final String explicitSiteContent
      when explicitSiteContent.trim().isNotEmpty) {
    return <String>[explicitSiteContent.trim()];
  }
  if (config.contentRoot case final String explicitContent
      when explicitContent.trim().isNotEmpty) {
    return <String>[explicitContent.trim()];
  }

  final discovered = <String>[];
  if (site.isNotEmpty) {
    for (final candidate in <String>[
      'sites/$site/src/content',
      'sites/$site/content',
    ]) {
      if (Directory(
        path.joinAll([canonicalRoot, ...path.posix.split(candidate)]),
      ).existsSync()) {
        discovered.add(candidate);
      }
    }
  }
  for (final candidate in const <String>['content', 'src/content']) {
    if (Directory(path.joinAll([canonicalRoot, ...path.posix.split(candidate)]))
        .existsSync()) {
      discovered.add(candidate);
    }
  }
  return discovered;
}

List<_CandidateFile> _collectPrimaryCandidates({
  required String canonicalRoot,
  required String site,
  required ReviewProjectConfig config,
  required String? rawSourceFile,
  required String safeSourceFile,
  required String? pageUrl,
}) {
  final rawVariants = <String>[];

  void addVariantsForPath(String basePath, {required bool endedWithSlash}) {
    if (basePath.isEmpty) return;
    rawVariants.add(basePath);

    if (endedWithSlash) {
      rawVariants.add('$basePath/index.md');
      rawVariants.add('$basePath.md');
    } else if (basePath.endsWith('/index.html')) {
      final stem = basePath.substring(
        0,
        basePath.length - '/index.html'.length,
      );
      rawVariants.add('$stem/index.md');
      if (stem.isNotEmpty) rawVariants.add('$stem.md');
    } else if (basePath.endsWith('.html')) {
      final stem = basePath.substring(0, basePath.length - '.html'.length);
      rawVariants.add('$stem.md');
      rawVariants.add('$stem/index.md');
    } else if (basePath.endsWith('/index.md')) {
      final stem = basePath.substring(0, basePath.length - '/index.md'.length);
      if (stem.isNotEmpty) rawVariants.add('$stem.md');
    } else if (basePath.endsWith('.md')) {
      final stem = basePath.substring(0, basePath.length - '.md'.length);
      rawVariants.add('$stem/index.md');
    } else if (path.posix.extension(basePath).isEmpty) {
      rawVariants.add('$basePath/index.md');
      rawVariants.add('$basePath.md');
    }
  }

  final rawTrimmed = rawSourceFile?.trim() ?? '';
  final endedWithSlash = rawTrimmed.endsWith('/');
  if (safeSourceFile.isNotEmpty) {
    addVariantsForPath(safeSourceFile, endedWithSlash: endedWithSlash);
  }

  if (pageUrl != null && pageUrl.trim().isNotEmpty) {
    final contentPrefixes = _resolveContentRoots(
      canonicalRoot: canonicalRoot,
      site: site,
      config: config,
    );
    var cleanUrl = _stripQueryAndFragment(pageUrl.trim());
    final urlEndedWithSlash = cleanUrl.endsWith('/');
    while (cleanUrl.startsWith('/')) {
      cleanUrl = cleanUrl.substring(1);
    }
    while (cleanUrl.endsWith('/')) {
      cleanUrl = cleanUrl.substring(0, cleanUrl.length - 1);
    }

    for (final contentPrefix in contentPrefixes) {
      if (cleanUrl.isEmpty) {
        rawVariants.add('$contentPrefix/index.md');
      } else {
        addVariantsForPath(
          '$contentPrefix/$cleanUrl',
          endedWithSlash: urlEndedWithSlash,
        );
      }
    }
  }

  final results = <_CandidateFile>[];
  final seen = <String>{};
  for (final variant in rawVariants) {
    final resolved = _resolveExistingRepoFile(canonicalRoot, variant);
    if (resolved != null && seen.add(resolved.relPath)) {
      results.add(resolved);
    }
  }
  return results;
}

List<_CandidateFile> _collectDelegatedPrimaryHints({
  required String canonicalRoot,
  required String site,
  required ReviewProjectConfig config,
  required List<_CandidateFile> primaryCandidates,
  required Set<String> skippedDirs,
}) {
  final hints = <_CandidateFile>[];
  final seen = <String>{
    for (final primary in primaryCandidates) primary.relPath,
  };

  void addHint(String relCandidate) {
    final resolved = _resolveExistingRepoFile(canonicalRoot, relCandidate);
    if (resolved != null && seen.add(resolved.relPath)) {
      hints.add(resolved);
    }
  }

  final siteCfg = site.isNotEmpty ? config.sites[site] : null;
  final includeRoots = <String>[
    ...?siteCfg?.includeRoots,
    if (site.isNotEmpty) 'sites/$site/src/_includes',
    'src/_includes',
    '_includes',
    'content/_includes',
  ];
  final componentRoots = <String>[
    ...?siteCfg?.componentRoots,
    if (site.isNotEmpty) ...<String>[
      'sites/$site/lib/src/pages',
      'sites/$site/lib/src/components/pages',
      'sites/$site/lib/src/components/sections',
      'sites/$site/lib/src/components/common',
      'sites/$site/lib/pages',
      'sites/$site/lib/components',
    ],
    'lib/src/pages',
    'lib/pages',
    'lib/src/components',
    'lib/components',
  ];

  final includePattern = RegExp(
    r'''\{%-?\s*include\s+['"]?([^'"\s%}]+)['"]?''',
  );
  final componentPattern = RegExp(r'<([A-Z][A-Za-z0-9_]*)\b');

  for (final primary in primaryCandidates) {
    final content = _readTextFileSafely(primary.absPath);
    if (content == null) continue;

    // 1. Liquid {% include 'path/to/partial.md' %} references.
    for (final match in includePattern.allMatches(content)) {
      final includePath = match.group(1);
      if (includePath == null || includePath.isEmpty) continue;
      for (final includeRoot in includeRoots) {
        addHint('$includeRoot/$includePath');
        if (path.posix.extension(includePath).isEmpty) {
          addHint('$includeRoot/$includePath.md');
          addHint('$includeRoot/$includePath.html');
        }
      }
    }

    // 2. Jaspr / MDX custom components like <HomePage /> or <CheckoutCard />.
    if (!primary.relPath.endsWith('.dart')) {
      for (final match in componentPattern.allMatches(content)) {
        final componentName = match.group(1);
        if (componentName == null) continue;
        final snakeName = _camelToSnakeCase(componentName);
        for (final compRoot in componentRoots) {
          addHint('$compRoot/$snakeName.dart');
        }
      }

      // 3. Data files adjacent to the primary content file (or home/ for root index).
      final primaryDir = path.posix.dirname(primary.relPath);
      if (path.posix.basename(primary.relPath) == 'index.md') {
        _collectDirectoryFiles(
          canonicalRoot: canonicalRoot,
          relativeDir: '$primaryDir/home',
          allowedExtensions: _dataExtensions,
          skippedDirs: skippedDirs,
          seen: seen,
          out: hints,
        );
      }
      if (primaryDir.isNotEmpty && primaryDir != '.') {
        _collectDirectoryFiles(
          canonicalRoot: canonicalRoot,
          relativeDir: primaryDir,
          allowedExtensions: _dataExtensions,
          skippedDirs: skippedDirs,
          seen: seen,
          out: hints,
        );
      }
    }
  }

  return hints;
}

List<_CandidateFile> _collectSecondaryCandidates({
  required String canonicalRoot,
  required String site,
  required ReviewProjectConfig config,
  required List<_CandidateFile> primaryCandidates,
  required Set<String> skippedDirs,
}) {
  final results = <_CandidateFile>[];
  final seen = <String>{
    for (final primary in primaryCandidates) primary.relPath,
  };

  // First add files explicitly referenced by the primary file.
  for (final hint in _collectDelegatedPrimaryHints(
    canonicalRoot: canonicalRoot,
    site: site,
    config: config,
    primaryCandidates: primaryCandidates,
    skippedDirs: skippedDirs,
  )) {
    if (seen.add(hint.relPath)) {
      results.add(hint);
    }
  }

  final siteCfg = site.isNotEmpty ? config.sites[site] : null;
  final collectedPool = <_CandidateFile>[];

  if (siteCfg != null &&
      (siteCfg.sourceRoots.isNotEmpty || siteCfg.dataRoots.isNotEmpty)) {
    for (final root in siteCfg.sourceRoots) {
      if (root.endsWith('/_data') || root == '_data') {
        _collectDirectoryFiles(
          canonicalRoot: canonicalRoot,
          relativeDir: root,
          allowedExtensions: _searchableExtensions,
          skippedDirs: skippedDirs,
          seen: seen,
          out: collectedPool,
        );
      }
    }
    for (final dataRoot in siteCfg.dataRoots) {
      _collectDirectoryFiles(
        canonicalRoot: canonicalRoot,
        relativeDir: dataRoot,
        allowedExtensions: _dataExtensions,
        skippedDirs: skippedDirs,
        seen: seen,
        out: collectedPool,
      );
    }
    for (final root in siteCfg.sourceRoots) {
      if (root.endsWith('/_data') || root == '_data') continue;
      _collectDirectoryFiles(
        canonicalRoot: canonicalRoot,
        relativeDir: root,
        allowedExtensions: _searchableExtensions,
        skippedDirs: skippedDirs,
        seen: seen,
        out: collectedPool,
      );
    }
  } else if (config.sourceRoots != null) {
    for (final root in config.sourceRoots!) {
      _collectDirectoryFiles(
        canonicalRoot: canonicalRoot,
        relativeDir: root,
        allowedExtensions: _searchableExtensions,
        skippedDirs: skippedDirs,
        seen: seen,
        out: collectedPool,
      );
    }
  } else {
    // Auto-discover project layout: support multi-site `sites/<site>/...`
    // workspaces as well as standard `lib/`, `content/`, `src/`, `web/`, etc.
    final siteRootDir = site.isNotEmpty
        ? Directory(path.join(canonicalRoot, 'sites', site))
        : null;
    if (siteRootDir != null && siteRootDir.existsSync()) {
      for (final sub in <String>[
        'sites/$site/src/_includes',
        'sites/$site/src/data',
        'sites/$site/content/_data',
      ]) {
        _collectDirectoryFiles(
          canonicalRoot: canonicalRoot,
          relativeDir: sub,
          allowedExtensions: _searchableExtensions,
          skippedDirs: skippedDirs,
          seen: seen,
          out: collectedPool,
        );
      }
      _collectDirectoryFiles(
        canonicalRoot: canonicalRoot,
        relativeDir: 'sites/$site/content',
        allowedExtensions: _dataExtensions,
        skippedDirs: skippedDirs,
        seen: seen,
        out: collectedPool,
      );
      for (final sub in <String>[
        'sites/$site/lib',
        'sites/$site/src',
        if (site != 'www') 'examples',
      ]) {
        _collectDirectoryFiles(
          canonicalRoot: canonicalRoot,
          relativeDir: sub,
          allowedExtensions: _searchableExtensions,
          skippedDirs: skippedDirs,
          seen: seen,
          out: collectedPool,
        );
      }
    } else {
      for (final root in defaultAutoSourceRoots) {
        _collectDirectoryFiles(
          canonicalRoot: canonicalRoot,
          relativeDir: root,
          allowedExtensions: _searchableExtensions,
          skippedDirs: skippedDirs,
          seen: seen,
          out: collectedPool,
        );
      }
    }
  }

  // Prefer hand-authored files over generated Dart files (*.g.dart,
  // *.freezed.dart, *.mapper.dart, *.gr.dart).
  results.addAll(
    collectedPool.where((file) => !_isGeneratedDartFile(file.relPath)),
  );
  results.addAll(
    collectedPool.where((file) => _isGeneratedDartFile(file.relPath)),
  );

  return results;
}

bool _isGeneratedDartFile(String relPath) =>
    relPath.endsWith('.mapper.dart') ||
    relPath.endsWith('.g.dart') ||
    relPath.endsWith('.freezed.dart') ||
    relPath.endsWith('.gr.dart');

void _collectDirectoryFiles({
  required String canonicalRoot,
  required String relativeDir,
  required Set<String> allowedExtensions,
  required Set<String> skippedDirs,
  required Set<String> seen,
  required List<_CandidateFile> out,
}) {
  final safeDirRel = sanitizeRepoRelativePath(
    canonicalRoot,
    relativeDir,
    canonicalRoot: canonicalRoot,
  );
  if (safeDirRel == null) return;

  final rootDir = Directory(
    path.joinAll([canonicalRoot, ...path.posix.split(safeDirRel)]),
  );
  if (!rootDir.existsSync()) return;

  void walk(Directory directory) {
    final List<FileSystemEntity> entries;
    try {
      entries = directory.listSync(followLinks: false)
        ..sort((a, b) => a.path.compareTo(b.path));
    } on FileSystemException {
      return;
    }

    for (final entry in entries) {
      final baseName = path.basename(entry.path);
      if (skippedDirs.contains(baseName)) continue;
      if (baseName.startsWith('.') && baseName != '_data') continue;

      if (entry is Directory) {
        walk(entry);
      } else if (entry is File) {
        final ext = path.extension(baseName).toLowerCase();
        if (!allowedExtensions.contains(ext)) continue;

        try {
          final realAbs = path.canonicalize(entry.resolveSymbolicLinksSync());
          if (!path.isWithin(canonicalRoot, realAbs)) continue;
          final rel = path.posix.joinAll(
            path.split(path.relative(realAbs, from: canonicalRoot)),
          );
          if (seen.add(rel)) {
            out.add((relPath: rel, absPath: realAbs));
          }
        } on FileSystemException {
          continue;
        }
      }
    }
  }

  walk(rootDir);
}

String? _readTextFileSafely(String absPath) {
  final file = File(absPath);
  try {
    final stat = file.statSync();
    if (stat.type != FileSystemEntityType.file ||
        stat.size > _maxSearchableFileBytes) {
      return null;
    }
    return file.readAsStringSync();
  } on FileSystemException {
    return null;
  }
}

String _camelToSnakeCase(String input) {
  final buffer = StringBuffer();
  for (var i = 0; i < input.length; i++) {
    final char = input[i];
    final isUpper = char.toUpperCase() == char && char.toLowerCase() != char;
    if (isUpper && i > 0) {
      final prev = input[i - 1];
      final prevIsUpper =
          prev.toUpperCase() == prev && prev.toLowerCase() != prev;
      final nextIsLower =
          i + 1 < input.length &&
          input[i + 1].toLowerCase() == input[i + 1] &&
          input[i + 1].toUpperCase() != input[i + 1];
      if (!prevIsUpper || nextIsLower) {
        buffer.write('_');
      }
    }
    buffer.write(char.toLowerCase());
  }
  return buffer.toString();
}

_LineMatch? _findExactMatch(String content, String rawQuery) {
  final query = rawQuery.trim();
  if (query.isEmpty) return null;

  final directIndex = content.indexOf(query);
  if (directIndex >= 0) {
    return _buildLineMatchFromRawSpan(
      content,
      directIndex,
      directIndex + query.length - 1,
    );
  }

  // Handle CRLF source files when query uses LF.
  if (content.contains('\r\n') &&
      query.contains('\n') &&
      !query.contains('\r\n')) {
    final crlfQuery = query.replaceAll('\n', '\r\n');
    final crlfIndex = content.indexOf(crlfQuery);
    if (crlfIndex >= 0) {
      return _buildLineMatchFromRawSpan(
        content,
        crlfIndex,
        crlfIndex + crlfQuery.length - 1,
      );
    }
  }

  return null;
}

_LineMatch? _findTolerantMatch(
  String content,
  String rawQuery, {
  required bool isDartSource,
}) {
  final collapsedQuery = _collapseQueryWhitespace(rawQuery);
  if (collapsedQuery.isEmpty) return null;

  final projection = _buildNormalizedProjection(
    content,
    isDartSource: isDartSource,
  );
  if (projection.text.isEmpty) return null;

  final candidateQueries = <String>[
    collapsedQuery,
    if (!isDartSource)
      _buildNormalizedProjection(rawQuery, isDartSource: false).text,
  ];

  for (final normalizedQuery in candidateQueries) {
    if (normalizedQuery.isEmpty) continue;
    final matchIdx = projection.text.indexOf(normalizedQuery);
    if (matchIdx >= 0) {
      final rawStart = projection.offsets[matchIdx];
      final rawEnd = projection.offsets[matchIdx + normalizedQuery.length - 1];
      return _buildLineMatchFromRawSpan(content, rawStart, rawEnd);
    }
  }

  // Case-insensitive fallback for CSS-transformed headings/labels (e.g. uppercase).
  if (collapsedQuery.length >= 4) {
    final lowerText = projection.text.toLowerCase();
    final lowerQuery = collapsedQuery.toLowerCase();
    if (lowerText.length == projection.offsets.length) {
      final lowerIdx = lowerText.indexOf(lowerQuery);
      if (lowerIdx >= 0) {
        final rawStart = projection.offsets[lowerIdx];
        final rawEnd = projection.offsets[lowerIdx + lowerQuery.length - 1];
        return _buildLineMatchFromRawSpan(content, rawStart, rawEnd);
      }
    }
  }

  return null;
}

_LineMatch? _findCompositeMultiLineMatch(
  String content,
  String rawQuery, {
  required bool isDartSource,
}) {
  if (!rawQuery.contains('\n')) return null;
  final segments = [
    for (final line in rawQuery.split('\n'))
      if (line.trim().length >= 3) line.trim(),
  ];
  if (segments.length < 2) return null;

  final matches = <_LineMatch>[];
  for (final segment in segments) {
    final match =
        _findExactMatch(content, segment) ??
        _findTolerantMatch(content, segment, isDartSource: isDartSource);
    if (match == null) return null;
    matches.add(match);
  }

  final minLine = matches.map((m) => m.startLine).reduce(math.min);
  final maxLine = matches.map((m) => m.endLine).reduce(math.max);
  if (maxLine - minLine > 35) return null;

  final lines = content.split('\n');
  return (
    startLine: minLine,
    endLine: maxLine,
    codeSnippet: extractCodeSnippet(lines, minLine, maxLine),
  );
}

String? _extractFlutterSelectorWidgetName(String? selector) {
  if (selector == null) return null;
  final trimmed = selector.trim();
  if (!trimmed.startsWith('flutter:')) return null;
  final match = RegExp(r'^flutter:([A-Za-z_$][A-Za-z0-9_$]*)')
      .firstMatch(trimmed);
  return match?.group(1);
}

_LineMatch? _findDartWidgetDeclarationMatch(
  String content,
  String widgetClassName,
) {
  final escaped = RegExp.escape(widgetClassName);
  final declPattern = RegExp(
    r'\b(?:class|mixin|enum|extension\s+type)\s+' + escaped + r'\b',
  );
  final lines = content.split('\n');
  for (var idx = 0; idx < lines.length; idx++) {
    final line = lines[idx].replaceAll('\r', '');
    if (line.trimLeft().startsWith('//')) continue;
    if (declPattern.hasMatch(line)) {
      final lineNumber = idx + 1;
      return (
        startLine: lineNumber,
        endLine: lineNumber,
        codeSnippet: extractCodeSnippet(lines, lineNumber, lineNumber),
      );
    }
  }
  return null;
}

_LineMatch? _findDartWidgetConstructorMatch(
  String content,
  String widgetClassName,
) {
  final escaped = RegExp.escape(widgetClassName);
  final ctorPattern = RegExp(
    r'\b' + escaped + r'(?:\.[a-zA-Z0-9_]+)?(?:\s*<[^>\n]+>)?\s*\(',
  );
  final lines = content.split('\n');
  for (var idx = 0; idx < lines.length; idx++) {
    final line = lines[idx].replaceAll('\r', '');
    if (line.trimLeft().startsWith('//')) continue;
    if (ctorPattern.hasMatch(line)) {
      final lineNumber = idx + 1;
      return (
        startLine: lineNumber,
        endLine: lineNumber,
        codeSnippet: extractCodeSnippet(lines, lineNumber, lineNumber),
      );
    }
  }
  return null;
}

String _collapseQueryWhitespace(String query) {
  final buffer = StringBuffer();
  var previousWasSpace = true;
  for (var i = 0; i < query.length; i++) {
    final ch = _normalizeVisibleChar(query[i]);
    if (_isWhitespaceChar(ch)) {
      if (!previousWasSpace) {
        buffer.write(' ');
        previousWasSpace = true;
      }
    } else {
      buffer.write(ch);
      previousWasSpace = false;
    }
  }
  final result = buffer.toString();
  return result.endsWith(' ') ? result.substring(0, result.length - 1) : result;
}

String _normalizeVisibleChar(String ch) => switch (ch) {
  '\u2018' || '\u2019' => "'",
  '\u201C' || '\u201D' => '"',
  '\u00A0' => ' ',
  _ => ch,
};

bool _isWhitespaceChar(String ch) =>
    ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r' || ch == '\u00A0';

bool _isWordChar(String ch) {
  if (ch.isEmpty) return false;
  final code = ch.codeUnitAt(0);
  return (code >= 0x30 && code <= 0x39) ||
      (code >= 0x41 && code <= 0x5A) ||
      (code >= 0x61 && code <= 0x7A);
}

({String text, List<int> offsets}) _buildNormalizedProjection(
  String content, {
  required bool isDartSource,
}) {
  final buffer = StringBuffer();
  final offsets = <int>[];
  var lastWasSpace = true;

  void emitSpace(int rawIndex) {
    if (!lastWasSpace && offsets.isNotEmpty) {
      buffer.write(' ');
      offsets.add(rawIndex);
      lastWasSpace = true;
    }
  }

  void emitVisible(String ch, int rawIndex) {
    final normalized = _normalizeVisibleChar(ch);
    if (_isWhitespaceChar(normalized)) {
      emitSpace(rawIndex);
      return;
    }
    buffer.write(normalized);
    offsets.add(rawIndex);
    lastWasSpace = false;
  }

  final length = content.length;
  final linkCloseSkips = <int, int>{};

  var i = 0;
  while (i < length) {
    if (linkCloseSkips.remove(i) case final resumeAfterLink?) {
      i = resumeAfterLink;
      continue;
    }

    final ch = content[i];

    if (isDartSource) {
      // Handle escaped quotes and newline escapes inside Dart strings.
      if (ch == r'\' && i + 1 < length) {
        final next = content[i + 1];
        if (next == "'" || next == '"' || next == r'\' || next == r'$') {
          emitVisible(next, i + 1);
          i += 2;
          continue;
        }
        if (next == 'n' || next == 't' || next == 'r') {
          emitSpace(i);
          i += 2;
          continue;
        }
      }

      // Join adjacent Dart string literals across lines:
      // `'First sentence. '\n  'Second sentence.'`
      if (ch == "'" || ch == '"') {
        final adjacentResume = _matchAdjacentDartStringQuote(content, i, ch);
        if (adjacentResume != null) {
          i = adjacentResume;
          continue;
        }
      }

      if (_isWhitespaceChar(ch)) {
        emitSpace(i);
      } else {
        emitVisible(ch, i);
      }
      i++;
      continue;
    }

    // Markdown / Liquid / HTML / YAML projection.
    final atLineStart = i == 0 || content[i - 1] == '\n';
    if (atLineStart) {
      final fenceMatch = RegExp(r'^[ \t]*(?:```+|~~~+)[^\n]*')
          .matchAsPrefix(content, i);
      if (fenceMatch != null) {
        emitSpace(i);
        i = fenceMatch.end;
        continue;
      }

      final alertMatch = RegExp(r'^[ \t]*:::[a-zA-Z0-9_-]*[ \t]*')
          .matchAsPrefix(content, i);
      if (alertMatch != null) {
        emitSpace(i);
        i = alertMatch.end;
        continue;
      }

      final linePrefixMatch = RegExp(
        r'^[ \t]*(?:#{1,6}[ \t]+|>[ \t]?|[-*+][ \t]+|\d+\.[ \t]+)',
      ).matchAsPrefix(content, i);
      if (linePrefixMatch != null) {
        emitSpace(i);
        i = linePrefixMatch.end;
        continue;
      }
    }

    if (content.startsWith('<!--', i)) {
      final closeIdx = content.indexOf('-->', i + 4);
      i = closeIdx >= 0 ? closeIdx + 3 : length;
      continue;
    }

    if (content.startsWith('<?', i)) {
      final closeIdx = content.indexOf('?>', i + 2);
      i = closeIdx >= 0 ? closeIdx + 2 : length;
      continue;
    }

    if (content.startsWith('{%', i)) {
      final closeIdx = content.indexOf('%}', i + 2);
      i = closeIdx >= 0 ? closeIdx + 2 : length;
      continue;
    }

    if (ch == '{' &&
        i + 1 < length &&
        (content[i + 1] == '#' || content[i + 1] == ':')) {
      final closeBrace = content.indexOf('}', i + 2);
      if (closeBrace >= 0 && !content.substring(i, closeBrace).contains('\n')) {
        i = closeBrace + 1;
        continue;
      }
    }

    if (ch == r'\' && i + 1 < length && !_isWhitespaceChar(content[i + 1])) {
      emitVisible(content[i + 1], i + 1);
      i += 2;
      continue;
    }

    if (ch == '!' && i + 1 < length && content[i + 1] == '[') {
      final linkTarget = _matchMarkdownLinkBrackets(content, i + 1);
      if (linkTarget != null) {
        linkCloseSkips[linkTarget.closeBracket] = linkTarget.afterTarget;
        i += 2;
        continue;
      }
    }

    if (ch == '[') {
      final linkTarget = _matchMarkdownLinkBrackets(content, i);
      if (linkTarget != null) {
        linkCloseSkips[linkTarget.closeBracket] = linkTarget.afterTarget;
        i++;
        continue;
      }
    }

    if (ch == '`') {
      while (i < length && content[i] == '`') {
        i++;
      }
      continue;
    }

    if (ch == '*' || ch == '~') {
      final prevSpace = i == 0 || _isWhitespaceChar(content[i - 1]);
      final nextSpace = i + 1 >= length || _isWhitespaceChar(content[i + 1]);
      if (!(prevSpace && nextSpace)) {
        while (i < length && content[i] == ch) {
          i++;
        }
        continue;
      }
    }

    if (ch == '_') {
      final prevWord = i > 0 && _isWordChar(content[i - 1]);
      var runEnd = i;
      while (runEnd < length && content[runEnd] == '_') {
        runEnd++;
      }
      final nextWord = runEnd < length && _isWordChar(content[runEnd]);
      if (!(prevWord && nextWord)) {
        i = runEnd;
        continue;
      }
    }

    if (ch == '<') {
      final autolinkMatch = RegExp(r'^<(https?://[^>\s]+)>')
          .matchAsPrefix(content, i);
      if (autolinkMatch != null) {
        final urlText = autolinkMatch.group(1)!;
        for (var k = 0; k < urlText.length; k++) {
          emitVisible(urlText[k], i + 1 + k);
        }
        i = autolinkMatch.end;
        continue;
      }

      final htmlTagMatch = RegExp(r'^</?[a-zA-Z][a-zA-Z0-9-]*(?:\s+[^>\n]*)?>')
          .matchAsPrefix(content, i);
      if (htmlTagMatch != null) {
        final tagLower = htmlTagMatch.group(0)!.toLowerCase();
        if (tagLower.startsWith('<br')) {
          emitSpace(i);
        }
        i = htmlTagMatch.end;
        continue;
      }
    }

    if (_isWhitespaceChar(ch)) {
      emitSpace(i);
    } else {
      emitVisible(ch, i);
    }
    i++;
  }

  var text = buffer.toString();
  if (text.endsWith(' ') && offsets.isNotEmpty) {
    text = text.substring(0, text.length - 1);
    offsets.removeLast();
  }

  return (text: text, offsets: offsets);
}

int? _matchAdjacentDartStringQuote(
  String content,
  int quoteIndex,
  String quote,
) {
  var j = quoteIndex + 1;
  var sawNewlineOrSpace = false;
  while (j < content.length) {
    final c = content[j];
    if (c == ' ' || c == '\t' || c == '\r' || c == '\n') {
      sawNewlineOrSpace = true;
      j++;
      continue;
    }
    if (c == '/' && j + 1 < content.length && content[j + 1] == '/') {
      final nextNewline = content.indexOf('\n', j + 2);
      if (nextNewline < 0) return null;
      sawNewlineOrSpace = true;
      j = nextNewline + 1;
      continue;
    }
    break;
  }

  if (!sawNewlineOrSpace || j >= content.length) return null;
  if (content[j] == 'r' && j + 1 < content.length && content[j + 1] == quote) {
    return j + 2;
  }
  if (content[j] == quote) {
    return j + 1;
  }
  return null;
}

({int closeBracket, int afterTarget})? _matchMarkdownLinkBrackets(
  String content,
  int openBracketIndex,
) {
  var depth = 0;
  var j = openBracketIndex;
  while (j < content.length) {
    final c = content[j];
    if (c == r'\') {
      j += 2;
      continue;
    }
    if (c == '\n' && j + 1 < content.length && content[j + 1] == '\n') {
      return null;
    }
    if (c == '[') {
      depth++;
    } else if (c == ']') {
      depth--;
      if (depth == 0) {
        if (j + 1 >= content.length) return null;
        final next = content[j + 1];
        if (next == '(') {
          var parenDepth = 1;
          var k = j + 2;
          while (k < content.length && parenDepth > 0) {
            if (content[k] == r'\') {
              k += 2;
              continue;
            }
            if (content[k] == '(') parenDepth++;
            if (content[k] == ')') parenDepth--;
            k++;
          }
          if (parenDepth == 0) {
            return (closeBracket: j, afterTarget: k);
          }
        } else if (next == '[') {
          final closeRef = content.indexOf(']', j + 2);
          if (closeRef >= 0 &&
              !content.substring(j + 2, closeRef).contains('\n')) {
            return (closeBracket: j, afterTarget: closeRef + 1);
          }
        }
        return null;
      }
    }
    j++;
  }
  return null;
}

String? _normalizeHeadingSlug(String? headingAnchor) {
  if (headingAnchor == null) return null;
  var slug = headingAnchor.trim();
  while (slug.startsWith('#')) {
    slug = slug.substring(1);
  }
  slug = slug.trim().toLowerCase();
  return slug.isEmpty ? null : slug;
}

_LineMatch? _findHeadingAnchorMatch(String content, String targetSlug) {
  final lines = content.split('\n');
  final explicitIdPatterns = [
    RegExp(r'\{#\s*' + RegExp.escape(targetSlug) + r'\b', caseSensitive: false),
    RegExp(
      r'''\bid\s*[:=]\s*['"]''' + RegExp.escape(targetSlug) + r'''['"]''',
      caseSensitive: false,
    ),
  ];
  final atxHeadingPattern = RegExp(
    r'^\s*#{1,6}\s+(.+?)(?:\s*\{#([a-zA-Z0-9_-]+)[^}]*\})?\s*$',
  );

  for (var idx = 0; idx < lines.length; idx++) {
    final line = lines[idx].replaceAll('\r', '');

    for (final pattern in explicitIdPatterns) {
      if (pattern.hasMatch(line)) {
        final lineNumber = idx + 1;
        return (
          startLine: lineNumber,
          endLine: lineNumber,
          codeSnippet: extractCodeSnippet(lines, lineNumber, lineNumber),
        );
      }
    }

    final headingMatch = atxHeadingPattern.firstMatch(line);
    if (headingMatch != null) {
      final rawHeadingText = headingMatch.group(1) ?? '';
      final explicitSlug = headingMatch.group(2)?.toLowerCase();
      if (explicitSlug == targetSlug ||
          _headingSlugsForText(rawHeadingText).contains(targetSlug)) {
        final lineNumber = idx + 1;
        return (
          startLine: lineNumber,
          endLine: lineNumber,
          codeSnippet: extractCodeSnippet(lines, lineNumber, lineNumber),
        );
      }
    }
  }

  return null;
}

Set<String> _headingSlugsForText(String rawHeading) {
  final plain = _buildNormalizedProjection(
    rawHeading,
    isDartSource: false,
  ).text.toLowerCase();
  if (plain.isEmpty) return const {};

  final gfmSlug = plain
      .replaceAll(RegExp(r'[^\w\s-]'), '')
      .trim()
      .replaceAll(RegExp(r'[\s]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');

  final dashedSlug = plain
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');

  return {
    if (gfmSlug.isNotEmpty) gfmSlug,
    if (dashedSlug.isNotEmpty) dashedSlug,
  };
}

_LineMatch _buildLineMatchFromRawSpan(
  String content,
  int rawStart,
  int rawEnd,
) {
  final maxIndex = math.max(0, content.length - 1);
  final clampedStart = math.min(math.max(0, rawStart), maxIndex);
  final clampedEnd = math.min(math.max(clampedStart, rawEnd), maxIndex);

  var startLine = 1;
  for (var i = 0; i < clampedStart; i++) {
    if (content.codeUnitAt(i) == 0x0A) startLine++;
  }

  var endLine = startLine;
  for (var i = clampedStart; i < clampedEnd; i++) {
    if (content.codeUnitAt(i) == 0x0A) endLine++;
  }

  final lines = content.split('\n');
  return (
    startLine: startLine,
    endLine: endLine,
    codeSnippet: extractCodeSnippet(lines, startLine, endLine),
  );
}

/// Extracts up to a 3-line (or capped multi-line) snippet surrounding
/// 1-based [startLine]..[endLine].
String extractCodeSnippet(List<String> rawLines, int startLine, int endLine) {
  if (rawLines.isEmpty) return '';
  final firstIdx = math.max(0, startLine - 2);
  var lastIdx = math.min(rawLines.length - 1, endLine);
  if (lastIdx - firstIdx + 1 < 3) {
    if (firstIdx == 0) {
      lastIdx = math.min(rawLines.length - 1, 2);
    } else if (lastIdx == rawLines.length - 1) {
      final adjustedFirst = math.max(0, rawLines.length - 3);
      return rawLines
          .sublist(adjustedFirst, lastIdx + 1)
          .map((line) => line.replaceAll('\r', ''))
          .join('\n');
    }
  }
  final cappedLast = math.min(lastIdx, firstIdx + 14);
  return rawLines
      .sublist(firstIdx, cappedLast + 1)
      .map((line) => line.replaceAll('\r', ''))
      .join('\n');
}
