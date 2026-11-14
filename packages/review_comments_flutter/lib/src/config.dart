// Copyright (c) 2026, Abdallah Shaban. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/foundation.dart';
import 'package:review_comments/review_comments.dart';

const bool _envProduction =
    bool.fromEnvironment('PRODUCTION') ||
    bool.fromEnvironment('REVIEW_COMMENTS_PRODUCTION');

const bool _envDisabled =
    bool.fromEnvironment('REVIEW_COMMENTS_DISABLED') ||
    bool.fromEnvironment('NO_REVIEW');

const String _rcMode = String.fromEnvironment('REVIEW_COMMENTS_MODE');
const String _drMode = String.fromEnvironment('DASH_REVIEW_MODE');
const String _envMode = _rcMode != '' ? _rcMode : _drMode;

const String _rcSite = String.fromEnvironment('REVIEW_COMMENTS_SITE');
const String _drSite = String.fromEnvironment('DASH_REVIEW_SITE');
const String _envSite = _rcSite != '' ? _rcSite : _drSite;

const String _rcServerPort = String.fromEnvironment(
  'REVIEW_COMMENTS_SERVER_PORT',
);
const String _drServerPort = String.fromEnvironment('DASH_REVIEW_SERVER_PORT');
const String _envServerPort = _rcServerPort != ''
    ? _rcServerPort
    : _drServerPort;

const String _rcPrNumber = String.fromEnvironment('REVIEW_COMMENTS_PR_NUMBER');
const String _drPrNumber = String.fromEnvironment('DASH_REVIEW_PR_NUMBER');
const String _envPrNumber = _rcPrNumber != '' ? _rcPrNumber : _drPrNumber;

const String _rcRepo = String.fromEnvironment('REVIEW_COMMENTS_REPO');
const String _drRepo = String.fromEnvironment('DASH_REVIEW_REPO');
const String _envRepo = _rcRepo != '' ? _rcRepo : _drRepo;

const String _rcCommitSha = String.fromEnvironment(
  'REVIEW_COMMENTS_COMMIT_SHA',
);
const String _drCommitSha = String.fromEnvironment('DASH_REVIEW_COMMIT_SHA');
const String _envCommitSha = _rcCommitSha != '' ? _rcCommitSha : _drCommitSha;

const String _rcHeadBranch = String.fromEnvironment(
  'REVIEW_COMMENTS_HEAD_BRANCH',
);
const String _drHeadBranch = String.fromEnvironment('DASH_REVIEW_HEAD_BRANCH');
const String _envHeadBranch = _rcHeadBranch != ''
    ? _rcHeadBranch
    : _drHeadBranch;

/// Configuration and activation safety gate for `ReviewCommentsOverlay` in
/// Flutter applications.
///
/// Reads `REVIEW_COMMENTS_*` (and legacy `DASH_REVIEW_*`) `--dart-define`
/// values while enforcing strict production safety:
/// - When `PRODUCTION=true`, the overlay is **always** disabled.
/// - In [kReleaseMode], the overlay is enabled **only** when [effectiveMode]
///   is explicitly `'local'` or `'preview'`.
/// - In [kDebugMode] and [kProfileMode], [enableInDebug] defaults to `true`,
///   activating `'local'` mode against port `'4099'` out of the box for
///   `flutter run -d chrome` unless explicitly disabled (`enabled: false`).
@immutable
final class ReviewCommentsConfig {
  /// Creates a [ReviewCommentsConfig] for `ReviewCommentsOverlay`.
  const ReviewCommentsConfig({
    this.mode,
    this.enabled,
    this.enableInDebug = true,
    this.isProduction,
    this.isReleaseMode,
    this.site,
    this.serverPort,
    this.prNumber,
    this.repo,
    this.commitSha,
    this.headBranch,
    this.defaultSourceFile = 'lib/main.dart',
    this.routeSourceFiles = const <String, String>{},
    this.feedbackFile = defaultReviewFeedbackFile,
    this.cliResolveCommand = '',
  });

  /// Explicit mode override (`'local'`, `'preview'`, or `'off'`).
  ///
  /// When `null`, falls back to `REVIEW_COMMENTS_MODE` / `DASH_REVIEW_MODE`,
  /// or `'local'` in non-release builds when [enableInDebug] is `true`.
  final String? mode;

  /// Explicit master toggle. Setting `false` disables the overlay even in
  /// debug mode.
  final bool? enabled;

  /// Whether debug and profile builds automatically enable `'local'` review
  /// mode on port `'4099'` when no explicit `--dart-define` mode is set.
  final bool enableInDebug;

  /// Optional override for `bool.fromEnvironment('PRODUCTION')`, primarily for
  /// testing production safety gating.
  final bool? isProduction;

  /// Optional override for [kReleaseMode], primarily for testing release
  /// safety gating.
  final bool? isReleaseMode;

  /// Logical site or application identifier (defaults to `'app'`).
  final String? site;

  /// Loopback port for `ReviewLocalServer` (defaults to `'4099'` in local
  /// mode when unset).
  final String? serverPort;

  /// Pull request number for preview mode.
  final String? prNumber;

  /// GitHub `owner/repo` slug for preview mode.
  final String? repo;

  /// Commit SHA associated with the preview build.
  final String? commitSha;

  /// Head branch name associated with the preview build.
  final String? headBranch;

  /// Fallback repository-relative Dart source file when a widget creation
  /// location is unavailable (for example, in release/preview web builds).
  final String defaultSourceFile;

  /// Optional map from normalized route paths (such as `'/details'`) to
  /// repository-relative Dart source files.
  final Map<String, String> routeSourceFiles;

  /// Relative path to the local agent feedback Markdown file displayed in UI.
  final String feedbackFile;

  /// Optional CLI command displayed in local agent prompts.
  final String cliResolveCommand;

  bool get _effectiveProduction => _envProduction || (isProduction ?? false);

  bool get _effectiveRelease => isReleaseMode ?? kReleaseMode;

  /// Resolved review mode (`'local'`, `'preview'`, or `''` when disabled).
  String get effectiveMode {
    if (_effectiveProduction || _envDisabled || enabled == false) {
      return '';
    }
    final raw = (mode ?? _envMode).trim().toLowerCase();
    if (raw == 'off' ||
        raw == 'false' ||
        raw == 'none' ||
        raw == 'disabled' ||
        raw == 'no') {
      return '';
    }
    if (raw == 'local' || raw == 'preview') {
      return raw;
    }
    if (raw.isNotEmpty) {
      // Unrecognized explicit mode value stays disabled.
      return '';
    }
    if (!_effectiveRelease && (enableInDebug || enabled == true)) {
      return 'local';
    }
    return '';
  }

  /// Whether the review overlay is active under the current build and config.
  bool get isEnabled {
    final resolved = effectiveMode;
    return !_effectiveProduction &&
        (resolved == 'local' || resolved == 'preview');
  }

  /// Effective loopback port string for local sync server connections.
  String get effectiveServerPort {
    if (serverPort != null) {
      return serverPort!.trim();
    }
    final fromEnv = _envServerPort.trim();
    if (fromEnv.isNotEmpty) {
      return fromEnv;
    }
    if (effectiveMode == 'local') {
      return '$defaultReviewServerPort';
    }
    return '';
  }

  /// Loopback HTTP origin URL (`http://127.0.0.1:<port>`) when configured.
  String get serverOrigin {
    final port = effectiveServerPort;
    return port.isNotEmpty ? 'http://127.0.0.1:$port' : '';
  }

  /// Effective site/app identifier.
  String get effectiveSite {
    final candidate = (site ?? _envSite).trim();
    return candidate.isNotEmpty ? candidate : 'app';
  }

  /// Effective pull request number string.
  String get effectivePrNumber => (prNumber ?? _envPrNumber).trim();

  /// Effective GitHub `owner/repo` slug.
  String get effectiveRepo => (repo ?? _envRepo).trim();

  /// Effective Git commit SHA.
  String get effectiveCommitSha => (commitSha ?? _envCommitSha).trim();

  /// Effective Git head branch name.
  String get effectiveHeadBranch => (headBranch ?? _envHeadBranch).trim();

  /// Resolves the fallback repository-relative source file for [routePath].
  String resolveSourceFileForRoute(String routePath) {
    final normalized = normalizeFlutterRoutePath(routePath);
    final mapped = routeSourceFiles[normalized];
    if (mapped != null && mapped.trim().isNotEmpty) {
      return mapped.trim();
    }
    return defaultSourceFile.trim();
  }

  /// Converts this Flutter configuration into a core [ReviewConfig].
  ReviewConfig toCoreConfig() => ReviewConfig(
    mode: effectiveMode,
    productionBuild: _effectiveProduction,
    site: effectiveSite,
    serverPort: effectiveServerPort,
    prNumber: effectivePrNumber,
    repo: effectiveRepo,
    commitSha: effectiveCommitSha,
    headBranch: effectiveHeadBranch,
    feedbackFile: feedbackFile,
    cliResolveCommand: cliResolveCommand,
  );
}

/// Normalizes a Flutter route name, pathname, or hash fragment (such as
/// `'#/details?tab=1'` or `'/details/'`) into a clean path starting with `'/'`.
String normalizeFlutterRoutePath(String? rawRoute) {
  if (rawRoute == null) {
    return '/';
  }
  var value = rawRoute.trim();
  if (value.isEmpty || value == '#' || value == '/#') {
    return '/';
  }
  if (value.startsWith('/#/')) {
    value = value.substring(2);
  } else if (value.startsWith('#/')) {
    value = value.substring(1);
  } else if (value.contains('#/')) {
    final hashIdx = value.indexOf('#/');
    value = value.substring(hashIdx + 1);
  }
  final queryIdx = value.indexOf('?');
  if (queryIdx != -1) {
    value = value.substring(0, queryIdx);
  }
  final hashIdx = value.indexOf('#');
  if (hashIdx != -1) {
    value = value.substring(0, hashIdx);
  }
  value = value.trim();
  if (value.isEmpty || value == '/') {
    return '/';
  }
  if (!value.startsWith('/')) {
    value = '/$value';
  }
  while (value.length > 1 && value.endsWith('/')) {
    value = value.substring(0, value.length - 1);
  }
  return value;
}
