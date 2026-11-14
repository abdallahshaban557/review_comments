// Copyright (c) 2026, Abdallah Shaban. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:meta/meta.dart';

/// A single visual review comment anchored to a rendered page or widget and
/// resolved repository source file.
@immutable
final class ReviewCommentModel {
  /// Creates an immutable [ReviewCommentModel].
  const ReviewCommentModel({
    required this.id,
    this.site = '',
    this.pageUrl = '/',
    this.pageTitle = '',
    this.sourceFile = '',
    this.resolvedFile = '',
    this.startLine,
    this.endLine,
    this.codeSnippet,
    this.anchorType = 'element',
    this.selectedText = '',
    this.prefixContext = '',
    this.suffixContext = '',
    this.selector = 'body',
    this.elementTag = 'div',
    this.elementText = '',
    this.headingAnchor = '',
    this.rectPct,
    required this.comment,
    this.author = 'reviewer',
    this.status = 'open',
    required this.createdAt,
    required this.updatedAt,
    this.githubUrl = '',
    this.commitSha = '',
    this.diffLine,
    this.diffMatched = false,
  });

  /// Deserializes a [ReviewCommentModel] from a JSON map.
  factory ReviewCommentModel.fromJson(Map<String, Object?> json) {
    Map<String, double>? parsedRect;
    if (json['rectPct'] case final Map<Object?, Object?> rawRect) {
      final mapped = <String, double>{};
      for (final entry in rawRect.entries) {
        if (entry.key is String && entry.value is num) {
          mapped[entry.key as String] = (entry.value as num).toDouble();
        }
      }
      if (mapped.isNotEmpty) {
        parsedRect = Map<String, double>.unmodifiable(mapped);
      }
    }

    final rawGithubUrl = _asString(json['githubUrl']);
    final safeGithubUrl = rawGithubUrl.startsWith('https://github.com/')
        ? rawGithubUrl
        : '';

    return ReviewCommentModel(
      id: _asString(json['id']),
      site: _asString(json['site']),
      pageUrl: _asString(json['pageUrl'], fallback: '/'),
      pageTitle: _asString(json['pageTitle']),
      sourceFile: _asString(json['sourceFile']),
      resolvedFile: _asString(json['resolvedFile']),
      startLine: _asIntOrNull(json['startLine']),
      endLine: _asIntOrNull(json['endLine']),
      codeSnippet: _asNullableString(json['codeSnippet']),
      anchorType: switch (_asString(json['anchorType'])) {
        'text' => 'text',
        'area' => 'area',
        _ => 'element',
      },
      selectedText: _asString(json['selectedText']),
      prefixContext: _asString(json['prefixContext']),
      suffixContext: _asString(json['suffixContext']),
      selector: _asString(json['selector'], fallback: 'body'),
      elementTag: _asString(json['elementTag'], fallback: 'div'),
      elementText: _asString(json['elementText']),
      headingAnchor: _asString(json['headingAnchor']),
      rectPct: parsedRect,
      comment: _asString(json['comment']),
      author: _asString(json['author'], fallback: 'reviewer'),
      status: _asString(json['status']) == 'resolved' ? 'resolved' : 'open',
      createdAt: _asString(json['createdAt']),
      updatedAt: _asString(json['updatedAt']),
      githubUrl: safeGithubUrl,
      commitSha: _asString(json['commitSha']),
      diffLine: _asIntOrNull(json['diffLine']),
      diffMatched: json['diffMatched'] == true,
    );
  }

  /// Unique comment identifier.
  final String id;

  /// Site or application identifier.
  final String site;

  /// Route or URL path where the comment was pinned.
  final String pageUrl;

  /// Human-readable page or screen title.
  final String pageTitle;

  /// Initial source file hint associated with the page or widget.
  final String sourceFile;

  /// Resolved repository-relative source file path.
  final String resolvedFile;

  /// 1-based starting line number in [resolvedFile], when resolved.
  final int? startLine;

  /// 1-based ending line number in [resolvedFile], when resolved.
  final int? endLine;

  /// Surrounding source code snippet captured by the local review server.
  final String? codeSnippet;

  /// Anchor kind: `'text'`, `'element'`, or `'area'`.
  final String anchorType;

  /// Selected text or extracted visible widget text.
  final String selectedText;

  /// Preceding text context used for fuzzy text range re-anchoring.
  final String prefixContext;

  /// Trailing text context used for fuzzy text range re-anchoring.
  final String suffixContext;

  /// CSS selector or `flutter:<WidgetType>` descriptor.
  final String selector;

  /// HTML tag name or Flutter widget type name.
  final String elementTag;

  /// Trimmed text summary of the inspected element or widget.
  final String elementText;

  /// Nearest `#heading-id` anchor when applicable.
  final String headingAnchor;

  /// Normalized `{x, y, w, h}` percentages (0..100) for pin/box positioning.
  final Map<String, double>? rectPct;

  /// Reviewer's comment body.
  final String comment;

  /// Reviewer display name or GitHub handle.
  final String author;

  /// Lifecycle status: `'open'` or `'resolved'`.
  final String status;

  /// ISO-8601 creation timestamp.
  final String createdAt;

  /// ISO-8601 last-update timestamp.
  final String updatedAt;

  /// Permalink on `https://github.com/` when posted in PR preview mode.
  final String githubUrl;

  /// Git commit SHA associated with a PR diff review comment.
  final String commitSha;

  /// Matched RIGHT-side diff line in a GitHub pull request.
  final int? diffLine;

  /// Whether this comment matched a RIGHT-side PR diff hunk line.
  final bool diffMatched;

  /// Formatted `file:startLine-endLine` label for prompts, chips, and CLI output.
  String get locationLabel {
    final targetFile = resolvedFile.isNotEmpty ? resolvedFile : sourceFile;
    if (targetFile.isEmpty) return '(unresolved source file)';
    if (startLine == null) return targetFile;
    if (endLine == null || endLine! <= startLine!) {
      return '$targetFile:$startLine';
    }
    return '$targetFile:$startLine-$endLine';
  }

  /// Returns a copy of this model with selected fields updated.
  ReviewCommentModel copyWith({
    String? comment,
    String? status,
    String? updatedAt,
    String? resolvedFile,
    int? startLine,
    int? endLine,
    String? codeSnippet,
    String? githubUrl,
    String? commitSha,
    int? diffLine,
    bool? diffMatched,
  }) => ReviewCommentModel(
    id: id,
    site: site,
    pageUrl: pageUrl,
    pageTitle: pageTitle,
    sourceFile: sourceFile,
    resolvedFile: resolvedFile ?? this.resolvedFile,
    startLine: startLine ?? this.startLine,
    endLine: endLine ?? this.endLine,
    codeSnippet: codeSnippet ?? this.codeSnippet,
    anchorType: anchorType,
    selectedText: selectedText,
    prefixContext: prefixContext,
    suffixContext: suffixContext,
    selector: selector,
    elementTag: elementTag,
    elementText: elementText,
    headingAnchor: headingAnchor,
    rectPct: rectPct,
    comment: comment ?? this.comment,
    author: author,
    status: status ?? this.status,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    githubUrl: githubUrl ?? this.githubUrl,
    commitSha: commitSha ?? this.commitSha,
    diffLine: diffLine ?? this.diffLine,
    diffMatched: diffMatched ?? this.diffMatched,
  );

  /// Serializes this comment to a JSON-compatible map.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'site': site,
    'pageUrl': pageUrl,
    'pageTitle': pageTitle,
    'sourceFile': sourceFile,
    'resolvedFile': resolvedFile,
    'startLine': startLine,
    'endLine': endLine,
    'codeSnippet': codeSnippet,
    'anchorType': anchorType,
    'selectedText': selectedText,
    'prefixContext': prefixContext,
    'suffixContext': suffixContext,
    'selector': selector,
    'elementTag': elementTag,
    'elementText': elementText,
    'headingAnchor': headingAnchor,
    'rectPct': rectPct,
    'comment': comment,
    'author': author,
    'status': status,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    if (githubUrl.isNotEmpty) 'githubUrl': githubUrl,
    if (commitSha.isNotEmpty) 'commitSha': commitSha,
    if (diffLine != null) 'diffLine': diffLine,
    if (diffMatched) 'diffMatched': diffMatched,
  };
}

/// Computes `open`, `resolved`, and `total` counts for [comments].
Map<String, int> computeReviewCommentCounts(
  Iterable<ReviewCommentModel> comments,
) {
  var open = 0;
  var resolved = 0;
  for (final item in comments) {
    if (item.status == 'resolved') {
      resolved++;
    } else {
      open++;
    }
  }
  return <String, int>{
    'open': open,
    'resolved': resolved,
    'total': open + resolved,
  };
}

/// Normalizes a page URL or SPA hash route so `/ui/layout/`, `/ui/layout`,
/// `/ui/layout/index.html`, and `/#/ui/layout` compare equal.
String normalizeReviewPageUrl(String rawUrl) {
  var value = rawUrl.trim();
  if (value.isEmpty) return '/';

  final hashRouteMatch = RegExp(r'^(?:https?:\/\/[^/#]+)?\/?#(\/.*)$')
      .firstMatch(value);
  if (hashRouteMatch != null) {
    value = hashRouteMatch.group(1)!;
  } else {
    final parsed = Uri.tryParse(value);
    if (parsed != null && (parsed.hasScheme || parsed.path.isNotEmpty)) {
      value = parsed.path;
    } else {
      final hIdx = value.indexOf('#');
      if (hIdx >= 0) value = value.substring(0, hIdx);
    }
  }

  final qIdx = value.indexOf('?');
  if (qIdx >= 0) value = value.substring(0, qIdx);

  if (!value.startsWith('/')) {
    value = '/$value';
  }
  if (value.toLowerCase().endsWith('/index.html')) {
    value = value.substring(0, value.length - '/index.html'.length);
  } else if (value.toLowerCase().endsWith('.html')) {
    value = value.substring(0, value.length - '.html'.length);
  }
  while (value.length > 1 && value.endsWith('/')) {
    value = value.substring(0, value.length - 1);
  }
  return value.isEmpty ? '/' : value;
}

String _asString(Object? value, {String fallback = ''}) {
  if (value is String) {
    final trimmed = value.trim();
    return trimmed.isNotEmpty ? value : fallback;
  }
  return fallback;
}

String? _asNullableString(Object? value) => value is String ? value : null;

int? _asIntOrNull(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim());
  return null;
}
