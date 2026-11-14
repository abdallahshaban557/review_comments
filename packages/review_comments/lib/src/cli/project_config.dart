import 'dart:io';

import 'package:path/path.dart' as path;

import 'review_source_locator.dart';

/// Default loopback port tried first by `ReviewLocalServer`.
const int defaultReviewServerPort = 4099;

/// Default repository-relative directory storing local visual review files.
const String defaultReviewDirectoryName = '.review_comments';

/// Default CLI resolve command shown in generated `feedback.md` instructions.
const String defaultCliResolveCommand = 'dart run review_comments resolve';

/// Default configuration file name checked in a repository root.
const String defaultReviewConfigFileName = 'review_comments.yaml';

/// Candidate source directories auto-discovered when [ReviewProjectConfig.sourceRoots]
/// is not explicitly set.
const List<String> defaultAutoSourceRoots = <String>[
  'lib',
  'content',
  'src',
  'web',
  'sites',
  'examples',
];

/// Site-specific directory configuration for multi-site workspaces.
final class ReviewSiteConfig {
  /// Optional content directory prefix used to map `pageUrl` paths to Markdown
  /// source files (for example, `'sites/docs/src/content'`).
  final String? contentRoot;

  /// Optional partial/include directories searched when a page contains
  /// Liquid `{% include '...' %}` directives.
  final List<String> includeRoots;

  /// Optional Dart component directories searched when a Markdown/MDX page
  /// embeds custom `<ComponentName />` tags.
  final List<String> componentRoots;

  /// Optional directories searched specifically for structured data files
  /// (`.yaml`, `.yml`, `.json`).
  final List<String> dataRoots;

  /// Ordered secondary source directories searched for text or widget matches.
  final List<String> sourceRoots;

  const ReviewSiteConfig({
    this.contentRoot,
    this.includeRoots = const <String>[],
    this.componentRoots = const <String>[],
    this.dataRoots = const <String>[],
    this.sourceRoots = const <String>[],
  });
}

/// Project-level configuration for `review_comments_cli` storage, prompts, and
/// source file resolution.
final class ReviewProjectConfig {
  /// Repository-relative directory storing `comments.json` and `feedback.md`.
  final String reviewDirectoryName;

  /// CLI command prefix rendered in `feedback.md` and `prompt` instructions.
  final String cliResolveCommand;

  /// Default site name used when requests do not specify one.
  final String defaultSite;

  /// Optional allowlist of valid site names (for example, `['docs', 'www']`).
  final List<String>? allowedSites;

  /// Optional content directory prefix for single-site content repositories.
  final String? contentRoot;

  /// Optional list of secondary source directories to search when the primary
  /// `sourceFile` does not match or is omitted.
  ///
  /// When `null`, existing directories among [defaultAutoSourceRoots] are
  /// discovered automatically.
  final List<String>? sourceRoots;

  /// Optional per-site source layout overrides keyed by site identifier.
  final Map<String, ReviewSiteConfig> sites;

  const ReviewProjectConfig({
    this.reviewDirectoryName = defaultReviewDirectoryName,
    this.cliResolveCommand = defaultCliResolveCommand,
    this.defaultSite = '',
    this.allowedSites,
    this.contentRoot,
    this.sourceRoots,
    this.sites = const <String, ReviewSiteConfig>{},
  });

  /// Preset matching the `flutter/website` (`docs` + `www`) monorepo layout.
  factory ReviewProjectConfig.flutterWebsite({
    String reviewDirectoryName = '.dash_review',
    String cliResolveCommand = 'dart run dash_site review resolve',
    String defaultSite = 'docs',
  }) => ReviewProjectConfig(
    reviewDirectoryName: reviewDirectoryName,
    cliResolveCommand: cliResolveCommand,
    defaultSite: defaultSite,
    allowedSites: const <String>['docs', 'www'],
    sites: const <String, ReviewSiteConfig>{
      'docs': ReviewSiteConfig(
        contentRoot: 'sites/docs/src/content',
        includeRoots: <String>['sites/docs/src/_includes'],
        sourceRoots: <String>[
          'sites/docs/src/_includes',
          'sites/docs/src/data',
          'sites/docs/lib/src',
          'examples',
        ],
      ),
      'www': ReviewSiteConfig(
        contentRoot: 'sites/www/content',
        componentRoots: <String>[
          'sites/www/lib/src/pages',
          'sites/www/lib/src/components/pages',
          'sites/www/lib/src/components/sections',
          'sites/www/lib/src/components/common',
        ],
        dataRoots: <String>['sites/www/content'],
        sourceRoots: <String>['sites/www/content/_data', 'sites/www/lib/src'],
      ),
    },
  );

  /// Loads [ReviewProjectConfig] from `review_comments.yaml` inside [repoRoot]
  /// if present and safely confined within [repoRoot], or returns defaults.
  factory ReviewProjectConfig.load(
    String repoRoot, {
    String configFileName = defaultReviewConfigFileName,
  }) {
    final safeRel = sanitizeRepoRelativePath(repoRoot, configFileName);
    if (safeRel == null) return const ReviewProjectConfig();

    final file = File(path.joinAll([repoRoot, ...path.posix.split(safeRel)]));
    if (!file.existsSync()) return const ReviewProjectConfig();

    try {
      final rawYaml = file.readAsStringSync();
      return ReviewProjectConfig.parseYaml(rawYaml);
    } on IOException {
      return const ReviewProjectConfig();
    }
  }

  /// Parses a `review_comments.yaml` document into a [ReviewProjectConfig].
  factory ReviewProjectConfig.parseYaml(String yamlContent) {
    final parsed = _parseSimpleYamlDocument(yamlContent);

    String? readString(Map<String, Object?> map, List<String> keys) {
      for (final key in keys) {
        final val = map[key];
        if (val is String && val.trim().isNotEmpty) {
          return val.trim();
        }
      }
      return null;
    }

    List<String>? readStringList(Map<String, Object?> map, List<String> keys) {
      for (final key in keys) {
        final val = map[key];
        if (val is List) {
          return [
            for (final item in val)
              if (item is String && item.trim().isNotEmpty) item.trim(),
          ];
        }
      }
      return null;
    }

    final reviewDir =
        readString(parsed, const [
          'reviewDirectoryName',
          'review_directory_name',
          'review_directory',
          'reviewDirectory',
        ]) ??
        defaultReviewDirectoryName;

    final resolveCmd =
        readString(parsed, const [
          'cliResolveCommand',
          'cli_resolve_command',
          'resolve_command',
        ]) ??
        defaultCliResolveCommand;

    final defaultSite =
        readString(parsed, const ['defaultSite', 'default_site']) ?? '';

    final allowedSites = readStringList(parsed, const [
      'allowedSites',
      'allowed_sites',
    ]);

    final contentRoot = readString(parsed, const [
      'contentRoot',
      'content_root',
    ]);

    final sourceRoots = readStringList(parsed, const [
      'sourceRoots',
      'source_roots',
    ]);

    final sites = <String, ReviewSiteConfig>{};
    if (parsed['sites'] case final Map<String, Object?> rawSites) {
      for (final entry in rawSites.entries) {
        final siteVal = entry.value;
        if (siteVal is List) {
          sites[entry.key] = ReviewSiteConfig(
            sourceRoots: [
              for (final item in siteVal)
                if (item is String && item.trim().isNotEmpty) item.trim(),
            ],
          );
        } else if (siteVal is Map<String, Object?>) {
          sites[entry.key] = ReviewSiteConfig(
            contentRoot: readString(siteVal, const [
              'contentRoot',
              'content_root',
            ]),
            includeRoots:
                readStringList(siteVal, const [
                  'includeRoots',
                  'include_roots',
                ]) ??
                const <String>[],
            componentRoots:
                readStringList(siteVal, const [
                  'componentRoots',
                  'component_roots',
                ]) ??
                const <String>[],
            dataRoots:
                readStringList(siteVal, const ['dataRoots', 'data_roots']) ??
                const <String>[],
            sourceRoots:
                readStringList(siteVal, const [
                  'sourceRoots',
                  'source_roots',
                ]) ??
                const <String>[],
          );
        }
      }
    }

    return ReviewProjectConfig(
      reviewDirectoryName: reviewDir,
      cliResolveCommand: resolveCmd,
      defaultSite: defaultSite,
      allowedSites: allowedSites,
      contentRoot: contentRoot,
      sourceRoots: sourceRoots,
      sites: sites,
    );
  }

  /// Creates a copy of this configuration with selected fields overridden.
  ReviewProjectConfig copyWith({
    String? reviewDirectoryName,
    String? cliResolveCommand,
    String? defaultSite,
    List<String>? allowedSites,
    String? contentRoot,
    List<String>? sourceRoots,
    Map<String, ReviewSiteConfig>? sites,
  }) => ReviewProjectConfig(
    reviewDirectoryName: reviewDirectoryName ?? this.reviewDirectoryName,
    cliResolveCommand: cliResolveCommand ?? this.cliResolveCommand,
    defaultSite: defaultSite ?? this.defaultSite,
    allowedSites: allowedSites ?? this.allowedSites,
    contentRoot: contentRoot ?? this.contentRoot,
    sourceRoots: sourceRoots ?? this.sourceRoots,
    sites: sites ?? this.sites,
  );

  /// Resolves [reviewDirectoryName] safely within [repoRoot], falling back to
  /// [defaultReviewDirectoryName] if the configured value attempts to escape
  /// [repoRoot].
  String safeReviewDirectoryRelativePath(String repoRoot) =>
      sanitizeRepoRelativePath(repoRoot, reviewDirectoryName) ??
      defaultReviewDirectoryName;

  /// Repository-relative POSIX path to `feedback.md`.
  String feedbackRelativePathFor(String repoRoot) =>
      '${safeReviewDirectoryRelativePath(repoRoot)}/feedback.md';

  /// Repository-relative POSIX path to `comments.json`.
  String commentsRelativePathFor(String repoRoot) =>
      '${safeReviewDirectoryRelativePath(repoRoot)}/comments.json';
}

Map<String, Object?> _parseSimpleYamlDocument(String content) {
  final root = <String, Object?>{};
  final lines = content.split('\n');

  String? currentTopKey;
  String? currentSiteKey;
  String? currentNestedListKey;

  for (final rawLine in lines) {
    final stripped = _stripYamlComment(rawLine);
    if (stripped.trim().isEmpty) continue;
    if (stripped.trim() == '---' || stripped.trim() == '...') continue;

    final indent = _leadingSpaces(stripped);
    final trimmed = stripped.trim();

    if (indent == 0) {
      currentSiteKey = null;
      currentNestedListKey = null;

      final kv = _splitKeyValue(trimmed);
      if (kv == null) continue;
      currentTopKey = kv.key;
      if (kv.value.isEmpty) {
        root[kv.key] = null;
      } else {
        root[kv.key] = _parseInlineValue(kv.value);
      }
      continue;
    }

    if (currentTopKey == null) continue;

    if (trimmed.startsWith('- ')) {
      final itemText = _unquoteYamlScalar(trimmed.substring(2).trim());
      if (currentTopKey == 'sites' && currentSiteKey != null) {
        final sitesMap =
            (root['sites'] ??= <String, Object?>{}) as Map<String, Object?>;
        if (currentNestedListKey != null) {
          final siteMap =
              (sitesMap[currentSiteKey] ??= <String, Object?>{})
                  as Map<String, Object?>;
          final list =
              (siteMap[currentNestedListKey] ??= <String>[]) as List<String>;
          if (itemText.isNotEmpty) list.add(itemText);
        } else {
          final list =
              (sitesMap[currentSiteKey] ??= <String>[]) as List<String>;
          if (itemText.isNotEmpty) list.add(itemText);
        }
      } else {
        final existing = root[currentTopKey];
        final list = existing is List<String> ? existing : <String>[];
        root[currentTopKey] = list;
        if (itemText.isNotEmpty) list.add(itemText);
      }
      continue;
    }

    if (currentTopKey == 'sites') {
      final sitesMap =
          (root['sites'] ??= <String, Object?>{}) as Map<String, Object?>;
      final kv = _splitKeyValue(trimmed);
      if (kv == null) continue;

      if (indent <= 2 || currentSiteKey == null) {
        currentSiteKey = kv.key;
        currentNestedListKey = null;
        if (kv.value.isEmpty) {
          sitesMap[currentSiteKey] = null;
        } else {
          sitesMap[currentSiteKey] = _parseInlineValue(kv.value);
        }
      } else {
        final existingSite = sitesMap[currentSiteKey];
        final siteMap = existingSite is Map<String, Object?>
            ? existingSite
            : <String, Object?>{};
        sitesMap[currentSiteKey] = siteMap;

        if (kv.value.isEmpty) {
          currentNestedListKey = kv.key;
          siteMap[kv.key] = <String>[];
        } else {
          currentNestedListKey = null;
          siteMap[kv.key] = _parseInlineValue(kv.value);
        }
      }
    }
  }

  return root;
}

int _leadingSpaces(String line) {
  var count = 0;
  while (count < line.length && (line[count] == ' ' || line[count] == '\t')) {
    count += line[count] == '\t' ? 2 : 1;
  }
  return count;
}

String _stripYamlComment(String rawLine) {
  var inSingle = false;
  var inDouble = false;
  for (var i = 0; i < rawLine.length; i++) {
    final ch = rawLine[i];
    if (ch == r'\' && inDouble && i + 1 < rawLine.length) {
      i++;
      continue;
    }
    if (ch == "'" && !inDouble) {
      inSingle = !inSingle;
    } else if (ch == '"' && !inSingle) {
      inDouble = !inDouble;
    } else if (ch == '#' && !inSingle && !inDouble) {
      if (i == 0 || rawLine[i - 1] == ' ' || rawLine[i - 1] == '\t') {
        return rawLine.substring(0, i).replaceAll('\r', '');
      }
    }
  }
  return rawLine.replaceAll('\r', '');
}

({String key, String value})? _splitKeyValue(String trimmed) {
  final colonIdx = trimmed.indexOf(':');
  if (colonIdx <= 0) return null;
  final key = _unquoteYamlScalar(trimmed.substring(0, colonIdx).trim());
  final value = trimmed.substring(colonIdx + 1).trim();
  if (key.isEmpty) return null;
  return (key: key, value: value);
}

Object _parseInlineValue(String rawValue) {
  if (rawValue.startsWith('[') && rawValue.endsWith(']')) {
    final inner = rawValue.substring(1, rawValue.length - 1).trim();
    if (inner.isEmpty) return <String>[];
    final items = <String>[];
    final current = StringBuffer();
    var inSingle = false;
    var inDouble = false;
    for (var i = 0; i < inner.length; i++) {
      final ch = inner[i];
      if (ch == r'\' && inDouble && i + 1 < inner.length) {
        current.write(inner[++i]);
        continue;
      }
      if (ch == "'" && !inDouble) {
        inSingle = !inSingle;
        current.write(ch);
      } else if (ch == '"' && !inSingle) {
        inDouble = !inDouble;
        current.write(ch);
      } else if (ch == ',' && !inSingle && !inDouble) {
        final cleaned = _unquoteYamlScalar(current.toString().trim());
        if (cleaned.isNotEmpty) items.add(cleaned);
        current.clear();
      } else {
        current.write(ch);
      }
    }
    final tail = _unquoteYamlScalar(current.toString().trim());
    if (tail.isNotEmpty) items.add(tail);
    return items;
  }
  return _unquoteYamlScalar(rawValue);
}

String _unquoteYamlScalar(String scalar) {
  if (scalar.length >= 2) {
    if (scalar.startsWith("'") && scalar.endsWith("'")) {
      return scalar.substring(1, scalar.length - 1).replaceAll("''", "'");
    }
    if (scalar.startsWith('"') && scalar.endsWith('"')) {
      return scalar
          .substring(1, scalar.length - 1)
          .replaceAll(r'\"', '"')
          .replaceAll(r'\\', r'\');
    }
  }
  return scalar;
}
