// Copyright (c) 2026, Abdallah Shaban. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';

import 'package:meta/meta.dart';

import 'review_constants.dart';

const bool _envProduction =
    bool.fromEnvironment('PRODUCTION', defaultValue: false) ||
    bool.fromEnvironment('REVIEW_COMMENTS_PRODUCTION', defaultValue: false);

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

/// Configuration for the visual review and GitHub PR comment overlay.
///
/// Supports both `REVIEW_COMMENTS_*` compile-time `--dart-define`s and legacy
/// `DASH_REVIEW_*` fallbacks via [ReviewConfig.fromEnvironment], as well as
/// programmatic configuration via [const ReviewConfig].
@immutable
final class ReviewConfig {
  /// Creates a [ReviewConfig] with explicit runtime values.
  const ReviewConfig({
    this.mode = '',
    this.productionBuild = _envProduction,
    this.site = '',
    this.serverPort = '',
    this.prNumber = '',
    this.repo = '',
    this.commitSha = '',
    this.headBranch = '',
    this.feedbackFile = defaultReviewFeedbackFile,
    this.cliResolveCommand = '',
  });

  /// Creates a [ReviewConfig] backed by `REVIEW_COMMENTS_*` (and legacy
  /// `DASH_REVIEW_*`) compile-time `--dart-define` flags.
  const ReviewConfig.fromEnvironment({
    String defaultSite = '',
    String defaultRepo = '',
    this.feedbackFile = defaultReviewFeedbackFile,
    this.cliResolveCommand = '',
  }) : mode = _envMode,
       productionBuild = _envProduction,
       site = _envSite != '' ? _envSite : defaultSite,
       serverPort = _envServerPort,
       prNumber = _envPrNumber,
       repo = _envRepo != '' ? _envRepo : defaultRepo,
       commitSha = _envCommitSha,
       headBranch = _envHeadBranch;

  /// Compile-time environment configuration snapshot.
  static const ReviewConfig environment = ReviewConfig.fromEnvironment();

  /// Active review mode (`'local'` or `'preview'`), or empty when disabled.
  final String mode;

  /// Whether `PRODUCTION=true` is active for this build.
  final bool productionBuild;

  /// Optional site or app identifier (e.g. `'docs'`, `'www'`, `'app'`).
  final String site;

  /// Loopback port for the local review sync server (e.g. `'4099'`).
  final String serverPort;

  /// GitHub pull request number for staged PR previews.
  final String prNumber;

  /// GitHub `owner/repo` slug used in preview mode.
  final String repo;

  /// Git commit SHA associated with the staged PR preview.
  final String commitSha;

  /// Head branch name associated with the staged PR preview.
  final String headBranch;

  /// Relative path to the local agent feedback Markdown file displayed in UI.
  final String feedbackFile;

  /// Optional custom CLI command shown in local agent prompts.
  final String cliResolveCommand;

  /// Hard safety gate ensuring production and non-review builds never emit
  /// review overlay markup or scripts.
  bool get isEnabled =>
      !_envProduction &&
      !productionBuild &&
      (mode == 'local' || mode == 'preview');

  /// Loopback HTTP origin URL when [serverPort] is configured.
  String get serverOrigin {
    final trimmedPort = serverPort.trim();
    return trimmedPort.isNotEmpty ? 'http://127.0.0.1:$trimmedPort' : '';
  }

  /// Normalized `owner/repo` slug, falling back to [fallback] when blank.
  String effectiveRepo([String fallback = '']) {
    final trimmed = repo.trim();
    return trimmed.isNotEmpty ? trimmed : fallback.trim();
  }

  /// Normalized site identifier, falling back to [fallback] when blank.
  String effectiveSite([String fallback = '']) {
    final trimmed = site.trim();
    return trimmed.isNotEmpty ? trimmed : fallback.trim();
  }

  /// Returns a copy of this configuration with selected fields overridden.
  ReviewConfig copyWith({
    String? mode,
    bool? productionBuild,
    String? site,
    String? serverPort,
    String? prNumber,
    String? repo,
    String? commitSha,
    String? headBranch,
    String? feedbackFile,
    String? cliResolveCommand,
  }) => ReviewConfig(
    mode: mode ?? this.mode,
    productionBuild: productionBuild ?? this.productionBuild,
    site: site ?? this.site,
    serverPort: serverPort ?? this.serverPort,
    prNumber: prNumber ?? this.prNumber,
    repo: repo ?? this.repo,
    commitSha: commitSha ?? this.commitSha,
    headBranch: headBranch ?? this.headBranch,
    feedbackFile: feedbackFile ?? this.feedbackFile,
    cliResolveCommand: cliResolveCommand ?? this.cliResolveCommand,
  );

  /// Builds the JSON-serializable per-page configuration map consumed by
  /// `<script id="dash-review-config" type="application/json">`.
  Map<String, Object?> toPageConfigMap({
    required String pageUrl,
    String pageTitle = '',
    String sourceFile = '',
    String defaultSite = '',
    String defaultRepo = '',
    String? feedbackFile,
    String? cliResolveCommand,
  }) {
    final resolvedFeedback = (feedbackFile ?? this.feedbackFile).trim();
    final resolvedCliCmd = (cliResolveCommand ?? this.cliResolveCommand).trim();
    return <String, Object?>{
      'mode': mode,
      'site': effectiveSite(defaultSite),
      'pageUrl': pageUrl,
      'pageTitle': pageTitle.trim(),
      'sourceFile': sourceFile.trim(),
      'serverOrigin': serverOrigin,
      'prNumber': prNumber.trim(),
      'repo': effectiveRepo(defaultRepo),
      'commitSha': commitSha.trim(),
      'headBranch': headBranch.trim(),
      if (resolvedFeedback.isNotEmpty &&
          resolvedFeedback != defaultReviewFeedbackFile)
        'feedbackFile': resolvedFeedback,
      if (resolvedCliCmd.isNotEmpty) 'cliResolveCommand': resolvedCliCmd,
    };
  }
}

/// Resolves a clean repository-relative source file path for a rendered page.
///
/// Prefers [explicitSourceFile] when non-empty; otherwise joins
/// [contentRootPrefix] and [pagePath] using POSIX forward slashes without
/// duplicating prefixes.
String normalizeReviewSourceFile(
  String contentRootPrefix,
  String pagePath, {
  String? explicitSourceFile,
}) {
  if (explicitSourceFile != null && explicitSourceFile.trim().isNotEmpty) {
    return _normalizeRepoRelativePath(explicitSourceFile);
  }

  final cleanPath = _normalizeRepoRelativePath(pagePath);
  if (cleanPath.isEmpty) {
    return '';
  }

  final cleanPrefix = _normalizeRepoRelativePath(contentRootPrefix);
  if (cleanPrefix.isEmpty ||
      cleanPath == cleanPrefix ||
      cleanPath.startsWith('$cleanPrefix/')) {
    return cleanPath;
  }

  return '$cleanPrefix/$cleanPath';
}

/// Encodes [value] as JSON safe for embedding inside an HTML `<script>` tag.
///
/// Escapes `</` as `<\/` and `<!--` as `\u003c!--` so untrusted or arbitrary
/// titles, URLs, or metadata can never break out of `<script>`.
String encodeReviewJsonForHtml(Object? value) =>
    jsonEncode(value).replaceAll('</', r'<\/').replaceAll('<!--', r'\u003c!--');

String _normalizeRepoRelativePath(String rawPath) {
  var normalized = rawPath.trim().replaceAll(r'\', '/');
  while (normalized.startsWith('./')) {
    normalized = normalized.substring(2);
  }
  while (normalized.startsWith('/')) {
    normalized = normalized.substring(1);
  }
  while (normalized.endsWith('/')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  return normalized;
}
