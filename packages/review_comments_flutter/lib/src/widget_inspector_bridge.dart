// Copyright (c) 2026, Abdallah Shaban. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:developer' as developer;
import 'dart:math' as math;

import 'package:cupertino_ui/cupertino_ui.dart' as cui;
// Support apps still importing legacy flutter/cupertino.dart or material.dart.
// ignore: deprecated_member_use
import 'package:flutter/cupertino.dart' as fcup;
// ignore: deprecated_member_use
import 'package:flutter/material.dart' as fmat;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart' as mui;

import 'config.dart';
import 'navigator_observer.dart';

const int _maxExtractedTextLength = 240;

/// Normalized user-code creation location extracted from a [Widget].
@immutable
final class WidgetSourceLocation {
  /// Creates a [WidgetSourceLocation].
  const WidgetSourceLocation({
    required this.sourceFile,
    required this.line,
    required this.column,
  });

  /// Repository-relative Dart source path (for example `lib/main.dart`).
  final String sourceFile;

  /// 1-based line number in [sourceFile].
  final int line;

  /// 1-based column number in [sourceFile].
  final int column;
}

/// Active route and source file metadata returned by `adapter.getPageContext()`.
@immutable
final class FlutterPageContext {
  /// Creates a [FlutterPageContext].
  const FlutterPageContext({
    required this.pageUrl,
    required this.pageTitle,
    required this.sourceFile,
  });

  /// Normalized route path (such as `'/'` or `'/details'`).
  final String pageUrl;

  /// Human-readable title for the active route or appbar.
  final String pageTitle;

  /// Fallback repository-relative Dart source file for the active route.
  final String sourceFile;

  /// Converts this context into a plain JSON-compatible map.
  Map<String, Object?> toMap() => <String, Object?>{
    'pageUrl': pageUrl,
    'pageTitle': pageTitle,
    'sourceFile': sourceFile,
  };
}

/// Viewport bounding rectangle in CSS / logical pixels.
@immutable
final class FlutterLocatedRect {
  /// Creates a [FlutterLocatedRect].
  const FlutterLocatedRect({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  /// Creates a [FlutterLocatedRect] from a Flutter [Rect].
  factory FlutterLocatedRect.fromRect(Rect rect) => FlutterLocatedRect(
    left: rect.left,
    top: rect.top,
    width: rect.width,
    height: rect.height,
  );

  /// Left coordinate in viewport logical pixels.
  final double left;

  /// Top coordinate in viewport logical pixels.
  final double top;

  /// Width in logical pixels.
  final double width;

  /// Height in logical pixels.
  final double height;

  /// Converts this rectangle into a `{left, top, width, height}` map.
  Map<String, double> toMap() => <String, double>{
    'left': left,
    'top': top,
    'width': width,
    'height': height,
  };
}

/// Hit-test inspection payload returned by `adapter.inspectPoint(x, y)`.
@immutable
final class FlutterInspectedPoint {
  /// Creates a [FlutterInspectedPoint].
  const FlutterInspectedPoint({
    required this.rect,
    required this.label,
    required this.elementTag,
    required this.selector,
    required this.selectedText,
    required this.elementText,
    this.headingAnchor = '',
    required this.sourceFile,
    this.startLine,
    this.endLine,
  });

  /// Viewport bounds of the inspected Flutter widget.
  final FlutterLocatedRect rect;

  /// Compact badge label displayed in the hover outline pill.
  final String label;

  /// Clean Flutter widget type name (for example `'FilledButton'` or `'Card'`).
  final String elementTag;

  /// Stable Flutter widget selector (`flutter:<WidgetType>[key=...]`).
  final String selector;

  /// Primary visible text snippet for diff/source line matching.
  final String selectedText;

  /// Full visible text summary inside the inspected widget subtree.
  final String elementText;

  /// Optional heading anchor slug (empty string for canvas widgets).
  final String headingAnchor;

  /// Resolved repository-relative Dart file (for example `'lib/main.dart'`).
  final String sourceFile;

  /// 1-based widget creation start line when `--track-widget-creation` is on.
  final int? startLine;

  /// 1-based widget creation end line when `--track-widget-creation` is on.
  final int? endLine;

  /// Converts this payload into the map structure expected by
  /// `window.__REVIEW_COMMENTS_ADAPTER__.inspectPoint`.
  Map<String, Object?> toMap() => <String, Object?>{
    'rect': rect.toMap(),
    'label': label,
    'elementTag': elementTag,
    'selector': selector,
    'selectedText': selectedText,
    'elementText': elementText,
    'headingAnchor': headingAnchor,
    'sourceFile': sourceFile,
    'startLine': startLine,
    'endLine': endLine,
  };
}

/// Region inspection payload returned by `adapter.inspectArea(rect)`.
@immutable
final class FlutterInspectedArea {
  /// Creates a [FlutterInspectedArea].
  const FlutterInspectedArea({
    required this.elementTag,
    required this.selector,
    required this.selectedText,
    required this.elementText,
    required this.sourceFile,
    this.startLine,
    this.endLine,
    required this.rectPct,
  });

  /// Enclosing widget type name.
  final String elementTag;

  /// Enclosing Flutter widget selector (`flutter:<WidgetType>[key=...]`).
  final String selector;

  /// Aggregated visible text across all widgets intersecting the area.
  final String selectedText;

  /// Aggregated visible text summary across intersecting widgets.
  final String elementText;

  /// Repository-relative Dart source path of the tightest enclosing user widget.
  final String sourceFile;

  /// 1-based creation line of the tightest enclosing user widget, if tracked.
  final int? startLine;

  /// 1-based creation end line of the tightest enclosing user widget, if tracked.
  final int? endLine;

  /// Viewport-normalized `{x, y, w, h}` percentages (`0..100`).
  final Map<String, double> rectPct;

  /// Converts this payload into the map structure expected by
  /// `window.__REVIEW_COMMENTS_ADAPTER__.inspectArea`.
  Map<String, Object?> toMap() => <String, Object?>{
    'elementTag': elementTag,
    'selector': selector,
    'selectedText': selectedText,
    'elementText': elementText,
    'sourceFile': sourceFile,
    'startLine': startLine,
    'endLine': endLine,
    'rectPct': rectPct,
  };
}

enum _WidgetTier {
  /// Leaf interactive/text widgets that act as atomic selection targets.
  atomic,

  /// Meaningful Material/Cupertino surfaces or custom user widgets.
  meaningfulContainer,

  /// Page-level fallback surfaces (such as `Scaffold`) when clicking whitespace.
  pageFallback,

  /// Internal layout/plumbing wrappers skipped during inspection.
  wrapper,
}

final class _EvaluatedHit {
  const _EvaluatedHit({
    required this.element,
    required this.bounds,
    required this.tier,
    required this.widgetType,
    required this.keyString,
    required this.directLocation,
    required this.nearestUserLocation,
  });

  final Element element;
  final Rect bounds;
  final _WidgetTier tier;
  final String widgetType;
  final String? keyString;
  final WidgetSourceLocation? directLocation;
  final WidgetSourceLocation? nearestUserLocation;
}

/// Live Flutter [Element] and [RenderBox] tree inspector bridging Flutter's
/// widget hierarchy to the review overlay.
class FlutterWidgetTreeInspector {
  /// Creates a [FlutterWidgetTreeInspector] rooted at [rootKey].
  FlutterWidgetTreeInspector({
    required this.rootKey,
    required this.config,
    this.navigatorObserver,
    this.fallbackRouteReader,
    this.fallbackTitleReader,
  });

  /// [GlobalKey] attached to the root wrapper inside `ReviewCommentsOverlay`.
  final GlobalKey rootKey;

  /// Active overlay configuration used for fallback route/source resolution.
  final ReviewCommentsConfig config;

  /// Optional [ReviewCommentsNavigatorObserver] tracking named route changes.
  final ReviewCommentsNavigatorObserver? navigatorObserver;

  /// Optional platform callback returning the browser URL/hash route.
  final String Function()? fallbackRouteReader;

  /// Optional platform callback returning `document.title`.
  final String Function()? fallbackTitleReader;

  /// Resolves the active [FlutterPageContext] (`pageUrl`, `pageTitle`,
  /// `sourceFile`) from the live Flutter route and widget tree.
  FlutterPageContext getPageContext() {
    final route = resolveCurrentRoute();
    final title = resolveCurrentPageTitle();
    final mappedSource = config.resolveSourceFileForRoute(route);
    final detectedSource = _detectTopScreenUserSourceFile();
    final effectiveSource =
        config.routeSourceFiles.containsKey(normalizeFlutterRoutePath(route))
        ? mappedSource
        : (detectedSource ?? mappedSource);
    return FlutterPageContext(
      pageUrl: route,
      pageTitle: title,
      sourceFile: effectiveSource,
    );
  }

  /// Resolves the currently active normalized Flutter route path.
  String resolveCurrentRoute() {
    final observed = navigatorObserver?.currentRoute;
    if (observed != null && observed.trim().isNotEmpty) {
      return normalizeFlutterRoutePath(observed);
    }
    if (fallbackRouteReader != null) {
      final fromPlatform = fallbackRouteReader!().trim();
      if (fromPlatform.isNotEmpty && fromPlatform != '/') {
        return normalizeFlutterRoutePath(fromPlatform);
      }
    }
    final defaultRoute =
        WidgetsBinding.instance.platformDispatcher.defaultRouteName;
    if (defaultRoute.trim().isNotEmpty && defaultRoute.trim() != '/') {
      return normalizeFlutterRoutePath(defaultRoute);
    }
    if (fallbackRouteReader != null) {
      return normalizeFlutterRoutePath(fallbackRouteReader!());
    }
    return '/';
  }

  /// Resolves a human-readable title from the active `AppBar`, `Title` widget,
  /// or browser document title.
  String resolveCurrentPageTitle() {
    final root = rootKey.currentContext;
    if (root is Element && root.mounted) {
      final appBarTitle = _findActiveAppBarOrTitleText(root);
      if (appBarTitle != null && appBarTitle.isNotEmpty) {
        return appBarTitle;
      }
    }
    if (fallbackTitleReader != null) {
      final docTitle = fallbackTitleReader!().trim();
      if (docTitle.isNotEmpty) {
        return docTitle;
      }
    }
    return navigatorObserver?.currentRouteTitle ?? '';
  }

  /// Inspects the deepest meaningful Flutter widget containing [viewportPoint]
  /// (relative to the Flutter view origin, with optional [viewOffset] added to
  /// returned viewport coordinates).
  FlutterInspectedPoint? inspectPoint(
    Offset viewportPoint, {
    Offset viewOffset = Offset.zero,
  }) {
    final rootContext = rootKey.currentContext;
    if (rootContext is! Element || !rootContext.mounted) {
      return null;
    }

    final localPoint = viewportPoint - viewOffset;
    final hit = _hitTestElementRecursive(
      rootContext,
      localPoint,
      clipBounds: null,
      inheritedUserLocation: null,
      isOverlayRoot: true,
    );
    if (hit == null) {
      return null;
    }

    final textSegments = collectVisibleTextSegments(hit.element);
    final fullText = _joinAndCapSegments(textSegments);
    final primaryText = textSegments.isEmpty
        ? ''
        : (textSegments.length == 1
              ? fullText
              : _capText(textSegments.first.trim()));

    final effectiveLocation =
        hit.directLocation ??
        (_isCloseWrapperLocation(hit) ? hit.nearestUserLocation : null);
    final fallbackSource =
        hit.nearestUserLocation?.sourceFile ??
        config.resolveSourceFileForRoute(resolveCurrentRoute());
    final sourceFile = effectiveLocation?.sourceFile ?? fallbackSource;
    final startLine = effectiveLocation?.line;

    final selector = formatFlutterSelector(
      widgetType: hit.widgetType,
      keyString: hit.keyString,
    );
    final label = hit.keyString != null && hit.keyString!.isNotEmpty
        ? '${hit.widgetType}#${hit.keyString}'
        : hit.widgetType;

    final shiftedBounds = hit.bounds.shift(viewOffset);
    return FlutterInspectedPoint(
      rect: FlutterLocatedRect.fromRect(shiftedBounds),
      label: label,
      elementTag: hit.widgetType,
      selector: selector,
      selectedText: primaryText,
      elementText: fullText,
      sourceFile: sourceFile,
      startLine: startLine,
      endLine: startLine,
    );
  }

  /// Inspects all visible Flutter widgets intersecting [viewportArea] and
  /// aggregates their visible text and tightest enclosing user widget metadata.
  FlutterInspectedArea? inspectArea(
    Rect viewportArea, {
    Size? viewportSize,
    Offset viewOffset = Offset.zero,
  }) {
    final rootContext = rootKey.currentContext;
    if (rootContext is! Element || !rootContext.mounted) {
      return null;
    }
    if (viewportArea.width <= 0 || viewportArea.height <= 0) {
      return null;
    }

    final localArea = viewportArea.shift(-viewOffset);
    final rootBox = _renderBoxIfReady(rootContext);
    final effectiveViewport =
        viewportSize ??
        rootBox?.size ??
        Size(math.max(1, viewportArea.right), math.max(1, viewportArea.bottom));

    final collectedTexts = <String>[];
    final seenTexts = <String>{};
    _EvaluatedHit? tightestEnclosing;
    _EvaluatedHit? bestIntersectingUserHit;
    var bestOverlapArea = 0.0;

    void visit(
      Element element, {
      required Rect? clipBounds,
      required WidgetSourceLocation? inheritedUserLocation,
      required bool isOverlayRoot,
    }) {
      if (!element.mounted || element.debugIsDefunct) {
        return;
      }
      final widget = element.widget;
      if (!isOverlayRoot && _isHiddenSubtree(element, widget)) {
        return;
      }

      final directLoc = isOverlayRoot
          ? null
          : extractWidgetSourceLocation(widget);
      final nextUserLoc = directLoc ?? inheritedUserLocation;
      var nextClip = clipBounds;

      if (!isOverlayRoot) {
        final box = _renderBoxIfReady(element);
        if (box != null) {
          final rawBounds = _globalBoundsOf(box);
          if (rawBounds != null &&
              rawBounds.width > 0 &&
              rawBounds.height > 0) {
            if (_clipsChildren(element, widget)) {
              nextClip = nextClip == null
                  ? rawBounds
                  : nextClip.intersect(rawBounds);
              if (nextClip.width <= 0 || nextClip.height <= 0) {
                return;
              }
            }
            final visibleBounds = nextClip == null
                ? rawBounds
                : rawBounds.intersect(nextClip);
            if (visibleBounds.width > 0 &&
                visibleBounds.height > 0 &&
                visibleBounds.overlaps(localArea)) {
              final leafText = _extractDirectLeafText(widget);
              if (leafText != null && leafText.isNotEmpty) {
                if (seenTexts.add(leafText)) {
                  collectedTexts.add(leafText);
                }
              }

              final tier = _classifyWidgetTier(
                widget,
                hasUserLocation: directLoc != null,
              );
              if (tier != _WidgetTier.wrapper) {
                final candidate = _EvaluatedHit(
                  element: element,
                  bounds: visibleBounds,
                  tier: tier,
                  widgetType: describeFlutterWidgetType(widget),
                  keyString: extractFlutterWidgetKey(widget.key),
                  directLocation: directLoc,
                  nearestUserLocation: nextUserLoc,
                );
                if (_containsRectApproximately(visibleBounds, localArea)) {
                  if (tightestEnclosing == null ||
                      _shouldPreferEnclosing(candidate, tightestEnclosing!)) {
                    tightestEnclosing = candidate;
                  }
                }
                final overlap = visibleBounds.intersect(localArea);
                final overlapArea =
                    math.max(0.0, overlap.width) *
                    math.max(0.0, overlap.height);
                if (overlapArea >= bestOverlapArea &&
                    (directLoc != null || bestIntersectingUserHit == null)) {
                  bestOverlapArea = overlapArea;
                  bestIntersectingUserHit = candidate;
                }
              }
            }
          }
        }
      }

      final children = _collectOnstageChildren(element);
      for (final child in children) {
        visit(
          child,
          clipBounds: nextClip,
          inheritedUserLocation: nextUserLoc,
          isOverlayRoot: false,
        );
      }
    }

    visit(
      rootContext,
      clipBounds: null,
      inheritedUserLocation: null,
      isOverlayRoot: true,
    );

    final chosen = tightestEnclosing ?? bestIntersectingUserHit;
    final aggregatedText = _joinAndCapSegments(collectedTexts);
    final chosenLoc = chosen?.directLocation ?? chosen?.nearestUserLocation;
    final sourceFile =
        chosenLoc?.sourceFile ??
        config.resolveSourceFileForRoute(resolveCurrentRoute());
    final startLine = chosenLoc?.line;
    final widgetType = chosen?.widgetType ?? 'FlutterView';
    final selector = chosen != null
        ? formatFlutterSelector(
            widgetType: chosen.widgetType,
            keyString: chosen.keyString,
          )
        : 'flutter:FlutterView';

    final vw = math.max(1.0, effectiveViewport.width);
    final vh = math.max(1.0, effectiveViewport.height);
    final rectPct = <String, double>{
      'x': _roundPct((viewportArea.left / vw) * 100.0),
      'y': _roundPct((viewportArea.top / vh) * 100.0),
      'w': _roundPct((viewportArea.width / vw) * 100.0),
      'h': _roundPct((viewportArea.height / vh) * 100.0),
    };

    return FlutterInspectedArea(
      elementTag: widgetType,
      selector: selector,
      selectedText: aggregatedText,
      elementText: aggregatedText,
      sourceFile: sourceFile,
      startLine: startLine,
      endLine: startLine,
      rectPct: rectPct,
    );
  }

  /// Dynamically locates the live viewport bounding rectangle for a saved
  /// comment record (`selector`, `elementText`, `selectedText`, `anchorType`,
  /// `startLine`), enabling pins to follow scrolling `ListView`s in real time.
  FlutterLocatedRect? locateCommentRect({
    required String selector,
    String anchorType = 'element',
    String elementText = '',
    String selectedText = '',
    int? startLine,
    Offset viewOffset = Offset.zero,
  }) {
    if (anchorType == 'area' || !selector.startsWith('flutter:')) {
      return null;
    }
    final rootContext = rootKey.currentContext;
    if (rootContext is! Element || !rootContext.mounted) {
      return null;
    }

    final parsed = parseFlutterSelector(selector);
    if (parsed == null) {
      return null;
    }

    final targetText =
        (elementText.trim().isNotEmpty ? elementText : selectedText)
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
    final targetPrimary = selectedText.replaceAll(RegExp(r'\s+'), ' ').trim();

    Rect? bestBounds;
    var bestScore = -1;

    void search(Element element, {required bool isOverlayRoot}) {
      if (!element.mounted || element.debugIsDefunct) {
        return;
      }
      final widget = element.widget;
      if (!isOverlayRoot && _isHiddenSubtree(element, widget)) {
        return;
      }

      if (!isOverlayRoot) {
        final keyStr = extractFlutterWidgetKey(widget.key);
        final typeName = describeFlutterWidgetType(widget);
        final keyMatches = parsed.keyString != null
            ? keyStr == parsed.keyString
            : true;
        final typeMatches =
            typeName == parsed.widgetType ||
            widget.runtimeType.toString().split('<').first == parsed.widgetType;

        if (keyMatches && (parsed.keyString != null || typeMatches)) {
          final box = _renderBoxIfReady(element);
          final bounds = box == null ? null : _globalBoundsOf(box);
          if (bounds != null && bounds.width > 0 && bounds.height > 0) {
            var score = 0;
            if (parsed.keyString != null && keyStr == parsed.keyString) {
              score += 100;
            }
            if (typeMatches) {
              score += 25;
            }
            if (startLine != null) {
              final loc = extractWidgetSourceLocation(widget);
              if (loc != null && loc.line == startLine) {
                score += 40;
              }
            }
            if (targetText.isNotEmpty || targetPrimary.isNotEmpty) {
              final liveText = collectVisibleText(element);
              if (targetText.isNotEmpty && liveText == targetText) {
                score += 60;
              } else if (targetPrimary.isNotEmpty &&
                  liveText == targetPrimary) {
                score += 55;
              } else if (targetPrimary.isNotEmpty &&
                  liveText.contains(targetPrimary)) {
                score += 30;
              } else if (targetText.isNotEmpty &&
                  targetText.contains(liveText) &&
                  liveText.isNotEmpty) {
                score += 20;
              } else if (parsed.keyString == null) {
                score = -1;
              }
            }
            if (score > bestScore) {
              bestScore = score;
              bestBounds = bounds;
            }
          }
        }
      }

      final children = _collectOnstageChildren(element);
      for (final child in children) {
        search(child, isOverlayRoot: false);
      }
    }

    search(rootContext, isOverlayRoot: true);
    if (bestBounds == null || bestScore < 20) {
      return null;
    }
    return FlutterLocatedRect.fromRect(bestBounds!.shift(viewOffset));
  }

  _EvaluatedHit? _hitTestElementRecursive(
    Element element,
    Offset point, {
    required Rect? clipBounds,
    required WidgetSourceLocation? inheritedUserLocation,
    required bool isOverlayRoot,
  }) {
    if (!element.mounted || element.debugIsDefunct) {
      return null;
    }
    final widget = element.widget;
    if (!isOverlayRoot && _isHiddenSubtree(element, widget)) {
      return null;
    }

    final directLoc = isOverlayRoot
        ? null
        : extractWidgetSourceLocation(widget);
    final nextUserLoc = directLoc ?? inheritedUserLocation;
    var nextClip = clipBounds;
    Rect? visibleSelfBounds;
    final selfTier = isOverlayRoot
        ? _WidgetTier.wrapper
        : _classifyWidgetTier(widget, hasUserLocation: directLoc != null);

    if (!isOverlayRoot) {
      final box = _renderBoxIfReady(element);
      if (box != null) {
        final rawBounds = _globalBoundsOf(box);
        if (rawBounds != null && rawBounds.width > 0 && rawBounds.height > 0) {
          if (_clipsChildren(element, widget)) {
            nextClip = nextClip == null
                ? rawBounds
                : nextClip.intersect(rawBounds);
            if (!nextClip.contains(point)) {
              return null;
            }
          }
          visibleSelfBounds = nextClip == null
              ? rawBounds
              : rawBounds.intersect(nextClip);
          if (visibleSelfBounds.width <= 0 || visibleSelfBounds.height <= 0) {
            visibleSelfBounds = null;
          }
        }
      }

      if (selfTier == _WidgetTier.atomic &&
          visibleSelfBounds != null &&
          visibleSelfBounds.contains(point)) {
        return _EvaluatedHit(
          element: element,
          bounds: visibleSelfBounds,
          tier: selfTier,
          widgetType: describeFlutterWidgetType(widget),
          keyString: extractFlutterWidgetKey(widget.key),
          directLocation: directLoc,
          nearestUserLocation: nextUserLoc,
        );
      }
    }

    final children = _collectOnstageChildren(element);
    for (var i = children.length - 1; i >= 0; i--) {
      final child = children[i];
      if (_isBlockingModalBarrier(child.widget)) {
        break;
      }
      final childHit = _hitTestElementRecursive(
        child,
        point,
        clipBounds: nextClip,
        inheritedUserLocation: nextUserLoc,
        isOverlayRoot: false,
      );
      if (childHit != null) {
        if (!isOverlayRoot &&
            visibleSelfBounds != null &&
            selfTier == _WidgetTier.meaningfulContainer &&
            directLoc != null &&
            _isCustomUserCompositeWidget(widget) &&
            _sameBoundsApproximately(visibleSelfBounds, childHit.bounds) &&
            childHit.tier != _WidgetTier.atomic &&
            childHit.keyString == null) {
          return _EvaluatedHit(
            element: element,
            bounds: visibleSelfBounds,
            tier: selfTier,
            widgetType: describeFlutterWidgetType(widget),
            keyString: extractFlutterWidgetKey(widget.key),
            directLocation: directLoc,
            nearestUserLocation: nextUserLoc,
          );
        }
        return childHit;
      }
    }

    if (!isOverlayRoot &&
        selfTier != _WidgetTier.wrapper &&
        visibleSelfBounds != null &&
        visibleSelfBounds.contains(point)) {
      return _EvaluatedHit(
        element: element,
        bounds: visibleSelfBounds,
        tier: selfTier,
        widgetType: describeFlutterWidgetType(widget),
        keyString: extractFlutterWidgetKey(widget.key),
        directLocation: directLoc,
        nearestUserLocation: nextUserLoc,
      );
    }

    return null;
  }

  String? _findActiveAppBarOrTitleText(Element root) {
    String? appBarText;
    String? titleWidgetTitle;

    void walk(Element element) {
      if (!element.mounted || element.debugIsDefunct) {
        return;
      }
      final widget = element.widget;
      if (_isHiddenSubtree(element, widget)) {
        return;
      }
      if (widget is Title && widget.title.trim().isNotEmpty) {
        titleWidgetTitle = widget.title.trim();
      }
      if (widget is mui.AppBar) {
        final text = widget.title != null
            ? _collectSpecificDescendantWidgetText(element, widget.title!)
            : collectVisibleText(element);
        if (text.isNotEmpty) {
          appBarText = text;
        }
      } else if (widget is mui.SliverAppBar) {
        final text = widget.title != null
            ? _collectSpecificDescendantWidgetText(element, widget.title!)
            : collectVisibleText(element);
        if (text.isNotEmpty) {
          appBarText = text;
        }
      } else if (widget is fmat.AppBar) {
        final text = widget.title != null
            ? _collectSpecificDescendantWidgetText(element, widget.title!)
            : collectVisibleText(element);
        if (text.isNotEmpty) {
          appBarText = text;
        }
      } else if (widget is fmat.SliverAppBar) {
        final text = widget.title != null
            ? _collectSpecificDescendantWidgetText(element, widget.title!)
            : collectVisibleText(element);
        if (text.isNotEmpty) {
          appBarText = text;
        }
      }
      final children = _collectOnstageChildren(element);
      for (final child in children) {
        walk(child);
      }
    }

    walk(root);
    return appBarText ?? titleWidgetTitle;
  }

  String? _detectTopScreenUserSourceFile() {
    final root = rootKey.currentContext;
    if (root is! Element || !root.mounted) {
      return null;
    }
    String? latestSource;
    void walk(Element element, {required int depth}) {
      if (!element.mounted || element.debugIsDefunct || depth > 28) {
        return;
      }
      final widget = element.widget;
      if (_isHiddenSubtree(element, widget)) {
        return;
      }
      if (widget is mui.Scaffold ||
          widget is cui.CupertinoPageScaffold ||
          widget is fmat.Scaffold ||
          widget is fcup.CupertinoPageScaffold) {
        final loc = extractWidgetSourceLocation(widget);
        if (loc != null) {
          latestSource = loc.sourceFile;
        }
      }
      final children = _collectOnstageChildren(element);
      for (final child in children) {
        walk(child, depth: depth + 1);
      }
    }

    walk(root, depth: 0);
    return latestSource;
  }
}

/// Collects normalized visible text strings from `Text`, `RichText`,
/// `SelectableText`, `EditableText`, `Tooltip`, and `Semantics` inside [root],
/// capped cleanly at 240 characters.
String collectVisibleText(Element root) =>
    _joinAndCapSegments(collectVisibleTextSegments(root));

/// Collects distinct visible text segments in paint order inside [root]
/// without duplicating internal `Text` -> `RichText` / `Semantics` nodes.
List<String> collectVisibleTextSegments(Element root) {
  final segments = <String>[];

  void walk(Element element) {
    if (!element.mounted || element.debugIsDefunct) {
      return;
    }
    final widget = element.widget;
    if (_isHiddenSubtree(element, widget)) {
      return;
    }

    if (widget is Icon) {
      // Skip Icon's internal RichText glyph from icon fonts (MaterialIcons).
      return;
    }

    if (widget is Text) {
      final raw =
          widget.data ??
          widget.textSpan?.toPlainText(
            includeSemanticsLabels: false,
            includePlaceholders: false,
          ) ??
          '';
      final cleaned = _normalizeWhitespace(raw);
      if (cleaned.isNotEmpty) {
        segments.add(cleaned);
      }
      return;
    }

    if (widget is mui.SelectableText) {
      final raw =
          widget.data ??
          widget.textSpan?.toPlainText(
            includeSemanticsLabels: false,
            includePlaceholders: false,
          ) ??
          '';
      final cleaned = _normalizeWhitespace(raw);
      if (cleaned.isNotEmpty) {
        segments.add(cleaned);
      }
      return;
    }

    if (widget is fmat.SelectableText) {
      final raw =
          widget.data ??
          widget.textSpan?.toPlainText(
            includeSemanticsLabels: false,
            includePlaceholders: false,
          ) ??
          '';
      final cleaned = _normalizeWhitespace(raw);
      if (cleaned.isNotEmpty) {
        segments.add(cleaned);
      }
      return;
    }

    if (widget is mui.TextField) {
      final val = _normalizeWhitespace(widget.controller?.text ?? '');
      if (val.isNotEmpty) {
        segments.add(val);
      } else {
        final label = _normalizeWhitespace(
          widget.decoration?.labelText ?? widget.decoration?.hintText ?? '',
        );
        if (label.isNotEmpty) {
          segments.add(label);
        }
      }
      return;
    }

    if (widget is fmat.TextField) {
      final val = _normalizeWhitespace(widget.controller?.text ?? '');
      if (val.isNotEmpty) {
        segments.add(val);
      } else {
        final label = _normalizeWhitespace(
          widget.decoration?.labelText ?? widget.decoration?.hintText ?? '',
        );
        if (label.isNotEmpty) {
          segments.add(label);
        }
      }
      return;
    }

    if (widget is EditableText) {
      final val = _normalizeWhitespace(widget.controller.text);
      if (val.isNotEmpty) {
        segments.add(val);
      }
      return;
    }

    if (widget is RichText) {
      final raw = widget.text.toPlainText(
        includeSemanticsLabels: false,
        includePlaceholders: false,
      );
      final cleaned = _normalizeWhitespace(raw);
      if (cleaned.isNotEmpty) {
        segments.add(cleaned);
      }
      final children = _collectOnstageChildren(element);
      for (final child in children) {
        walk(child);
      }
      return;
    }

    if (widget is mui.Tooltip) {
      final beforeCount = segments.length;
      final children = _collectOnstageChildren(element);
      for (final child in children) {
        walk(child);
      }
      if (segments.length == beforeCount) {
        final msg = _normalizeWhitespace(
          widget.message ??
              widget.richMessage?.toPlainText(
                includeSemanticsLabels: false,
                includePlaceholders: false,
              ) ??
              '',
        );
        if (msg.isNotEmpty) {
          segments.add(msg);
        }
      }
      return;
    }

    if (widget is fmat.Tooltip) {
      final beforeCount = segments.length;
      final children = _collectOnstageChildren(element);
      for (final child in children) {
        walk(child);
      }
      if (segments.length == beforeCount) {
        final msg = _normalizeWhitespace(
          widget.message ??
              widget.richMessage?.toPlainText(
                includeSemanticsLabels: false,
                includePlaceholders: false,
              ) ??
              '',
        );
        if (msg.isNotEmpty) {
          segments.add(msg);
        }
      }
      return;
    }

    if (widget is Semantics) {
      final beforeCount = segments.length;
      final children = _collectOnstageChildren(element);
      for (final child in children) {
        walk(child);
      }
      if (segments.length == beforeCount) {
        final semText = _normalizeWhitespace(
          widget.properties.label ??
              widget.properties.value ??
              widget.properties.tooltip ??
              '',
        );
        if (semText.isNotEmpty) {
          segments.add(semText);
        }
      }
      return;
    }

    final children = _collectOnstageChildren(element);
    for (final child in children) {
      walk(child);
    }
  }

  walk(root);
  return segments;
}

String? _extractDirectLeafText(Widget widget) {
  if (widget is Text) {
    final cleaned = _normalizeWhitespace(
      widget.data ??
          widget.textSpan?.toPlainText(
            includeSemanticsLabels: false,
            includePlaceholders: false,
          ) ??
          '',
    );
    return cleaned.isEmpty ? null : cleaned;
  }
  if (widget is mui.SelectableText) {
    final cleaned = _normalizeWhitespace(
      widget.data ??
          widget.textSpan?.toPlainText(
            includeSemanticsLabels: false,
            includePlaceholders: false,
          ) ??
          '',
    );
    return cleaned.isEmpty ? null : cleaned;
  }
  if (widget is fmat.SelectableText) {
    final cleaned = _normalizeWhitespace(
      widget.data ??
          widget.textSpan?.toPlainText(
            includeSemanticsLabels: false,
            includePlaceholders: false,
          ) ??
          '',
    );
    return cleaned.isEmpty ? null : cleaned;
  }
  if (widget is EditableText) {
    final cleaned = _normalizeWhitespace(widget.controller.text);
    return cleaned.isEmpty ? null : cleaned;
  }
  if (widget is RichText) {
    final cleaned = _normalizeWhitespace(
      widget.text.toPlainText(
        includeSemanticsLabels: false,
        includePlaceholders: false,
      ),
    );
    return cleaned.isEmpty ? null : cleaned;
  }
  if (widget is mui.Tooltip) {
    final cleaned = _normalizeWhitespace(
      widget.message ??
          widget.richMessage?.toPlainText(
            includeSemanticsLabels: false,
            includePlaceholders: false,
          ) ??
          '',
    );
    return cleaned.isEmpty ? null : cleaned;
  }
  if (widget is fmat.Tooltip) {
    final cleaned = _normalizeWhitespace(
      widget.message ??
          widget.richMessage?.toPlainText(
            includeSemanticsLabels: false,
            includePlaceholders: false,
          ) ??
          '',
    );
    return cleaned.isEmpty ? null : cleaned;
  }
  if (widget is Semantics) {
    final cleaned = _normalizeWhitespace(
      widget.properties.label ??
          widget.properties.value ??
          widget.properties.tooltip ??
          '',
    );
    return cleaned.isEmpty ? null : cleaned;
  }
  return null;
}

/// Extracts the user-authored [WidgetSourceLocation] of [widget] when
/// `--track-widget-creation` is enabled, returning `null` for framework/pub
/// widgets or builds without creation tracking.
WidgetSourceLocation? extractWidgetSourceLocation(Widget widget) {
  final location = developer.CreationLocation.of(widget);
  if (location == null) {
    return null;
  }
  final rawFile = location.file;
  if (isFrameworkOrExternalCreationUri(rawFile)) {
    return null;
  }
  final normalized = normalizeWidgetSourceFile(rawFile);
  if (normalized.isEmpty || location.line <= 0) {
    return null;
  }
  return WidgetSourceLocation(
    sourceFile: normalized,
    line: location.line,
    column: location.column,
  );
}

/// Returns `true` when [rawUri] belongs to the Dart/Flutter SDK, Material or
/// Cupertino UI packages, pub cache, or internal `review_comments_*` library
/// code rather than the user's app.
bool isFrameworkOrExternalCreationUri(String rawUri) {
  final clean = rawUri.trim().replaceAll(r'\', '/');
  if (clean.isEmpty ||
      clean.startsWith('dart:') ||
      clean.startsWith('org-dartlang-sdk:')) {
    return true;
  }
  if (clean.contains('/.pub-cache/') ||
      clean.contains('/hosted/pub.dev/') ||
      clean.contains('/packages/flutter/') ||
      clean.contains('/packages/flutter_test/') ||
      clean.contains('/packages/flutter_web_plugins/') ||
      clean.contains('/packages/flutter_localizations/') ||
      clean.contains('/packages/material_ui/') ||
      clean.contains('/packages/cupertino_ui/') ||
      clean.contains('/packages/material_color_utilities/') ||
      clean.contains('/packages/review_comments_flutter/lib/') ||
      clean.contains('/packages/review_comments_core/')) {
    return true;
  }
  if (clean.startsWith('package:flutter/') ||
      clean.startsWith('package:flutter_test/') ||
      clean.startsWith('package:flutter_web_plugins/') ||
      clean.startsWith('package:flutter_localizations/') ||
      clean.startsWith('package:material_ui/') ||
      clean.startsWith('package:cupertino_ui/') ||
      clean.startsWith('package:material_color_utilities/') ||
      clean.startsWith('package:review_comments_flutter/') ||
      clean.startsWith('package:review_comments_core/')) {
    return true;
  }
  if (clean.startsWith('org-dartlang-app:///packages/flutter/') ||
      clean.startsWith('org-dartlang-app:///packages/material_ui/') ||
      clean.startsWith('org-dartlang-app:///packages/cupertino_ui/') ||
      clean.startsWith(
        'org-dartlang-app:///packages/review_comments_flutter/',
      )) {
    return true;
  }
  return false;
}

/// Normalizes a Dart widget creation URI (`file:///.../lib/foo.dart`,
/// `package:my_app/foo.dart`, or `org-dartlang-app:///packages/my_app/foo.dart`)
/// into a repository-relative path such as `lib/foo.dart`.
String normalizeWidgetSourceFile(String rawUri) {
  var value = rawUri.trim().replaceAll(r'\', '/');
  if (value.isEmpty) {
    return '';
  }

  final qIdx = value.indexOf('?');
  if (qIdx != -1) {
    value = value.substring(0, qIdx);
  }
  final hIdx = value.indexOf('#');
  if (hIdx != -1) {
    value = value.substring(0, hIdx);
  }

  if (value.startsWith('package:')) {
    final withoutScheme = value.substring('package:'.length);
    final slashIdx = withoutScheme.indexOf('/');
    if (slashIdx != -1 && slashIdx + 1 < withoutScheme.length) {
      return 'lib/${withoutScheme.substring(slashIdx + 1)}';
    }
    return '';
  }

  if (value.startsWith('org-dartlang-app:')) {
    final parsed = Uri.tryParse(value);
    final path = (parsed?.path ?? value.replaceFirst('org-dartlang-app:', ''))
        .replaceAll(RegExp(r'^/+'), '');
    if (path.startsWith('packages/')) {
      final rest = path.substring('packages/'.length);
      final slashIdx = rest.indexOf('/');
      if (slashIdx != -1 && slashIdx + 1 < rest.length) {
        return 'lib/${rest.substring(slashIdx + 1)}';
      }
    }
    final libIdx = path.lastIndexOf('/lib/');
    if (libIdx != -1) {
      return path.substring(libIdx + 1);
    }
    if (path.startsWith('lib/') || path.startsWith('test/')) {
      return path;
    }
    return path.endsWith('.dart') ? 'lib/$path' : path;
  }

  if (value.startsWith('http://') || value.startsWith('https://')) {
    final parsed = Uri.tryParse(value);
    final path = parsed?.path ?? '';
    final pkgIdx = path.indexOf('/packages/');
    if (pkgIdx != -1) {
      final rest = path.substring(pkgIdx + '/packages/'.length);
      final slashIdx = rest.indexOf('/');
      if (slashIdx != -1 && slashIdx + 1 < rest.length) {
        return 'lib/${rest.substring(slashIdx + 1)}';
      }
    }
    final libIdx = path.lastIndexOf('/lib/');
    if (libIdx != -1) {
      return path.substring(libIdx + 1);
    }
  }

  if (value.startsWith('file:')) {
    final parsed = Uri.tryParse(value);
    if (parsed != null && parsed.path.isNotEmpty) {
      value = parsed.path.replaceAll(r'\', '/');
    } else {
      value = value.replaceFirst(RegExp(r'^file:/+'), '/');
    }
  }

  final libIdx = value.lastIndexOf('/lib/');
  if (libIdx != -1) {
    return value.substring(libIdx + 1);
  }
  final testIdx = value.lastIndexOf('/test/');
  if (testIdx != -1) {
    return value.substring(testIdx + 1);
  }
  if (value.startsWith('lib/') || value.startsWith('test/')) {
    return value;
  }
  return value;
}

/// Formats a stable Flutter widget selector (`flutter:<WidgetType>` or
/// `flutter:<WidgetType>[key=<key>]`).
String formatFlutterSelector({required String widgetType, String? keyString}) {
  if (keyString != null && keyString.isNotEmpty) {
    return 'flutter:$widgetType[key=$keyString]';
  }
  return 'flutter:$widgetType';
}

/// Parses a `flutter:<WidgetType>[key=...]` selector string.
({String widgetType, String? keyString})? parseFlutterSelector(
  String selector,
) {
  final trimmed = selector.trim();
  if (!trimmed.startsWith('flutter:')) {
    return null;
  }
  final rest = trimmed.substring('flutter:'.length);
  if (rest.isEmpty) {
    return null;
  }
  final keyStart = rest.indexOf('[key=');
  if (keyStart != -1 && rest.endsWith(']')) {
    final type = rest.substring(0, keyStart).trim();
    final keyVal = rest.substring(keyStart + '[key='.length, rest.length - 1);
    if (type.isEmpty) {
      return null;
    }
    return (widgetType: type, keyString: keyVal.isEmpty ? null : keyVal);
  }
  return (widgetType: rest, keyString: null);
}

/// Extracts a clean human-readable key identifier from [key], ignoring private
/// framework keys.
String? extractFlutterWidgetKey(Key? key) {
  if (key == null) {
    return null;
  }
  if (key is ValueKey<Object?>) {
    final val = key.value;
    if (val == null) {
      return null;
    }
    final text = '$val'.trim();
    if (text.isEmpty || text.startsWith('_')) {
      return null;
    }
    return text;
  }
  if (key is GlobalObjectKey<State<StatefulWidget>>) {
    final text = '${key.value}'.trim();
    return text.isEmpty || text.startsWith('_') ? null : text;
  }
  return null;
}

/// Returns an unminified, human-readable widget type name using `is` checks
/// across `material_ui`, `cupertino_ui`, `flutter/widgets`, and legacy
/// `flutter/material` (preserving clean names even in dart2js `-O4` release
/// builds) and `runtimeType` for custom user widgets.
String describeFlutterWidgetType(Widget widget) {
  if (widget is mui.FilledButton || widget is fmat.FilledButton) {
    return 'FilledButton';
  }
  if (widget is mui.ElevatedButton || widget is fmat.ElevatedButton) {
    return 'ElevatedButton';
  }
  if (widget is mui.OutlinedButton || widget is fmat.OutlinedButton) {
    return 'OutlinedButton';
  }
  if (widget is mui.TextButton || widget is fmat.TextButton) {
    return 'TextButton';
  }
  if (widget is mui.IconButton || widget is fmat.IconButton) {
    return 'IconButton';
  }
  if (widget is mui.FloatingActionButton ||
      widget is fmat.FloatingActionButton) {
    return 'FloatingActionButton';
  }
  if (widget is cui.CupertinoButton || widget is fcup.CupertinoButton) {
    return 'CupertinoButton';
  }
  if (widget is mui.SegmentedButton<Object?> ||
      widget is fmat.SegmentedButton<Object?>) {
    return 'SegmentedButton';
  }
  if (widget is mui.PopupMenuButton || widget is fmat.PopupMenuButton) {
    return 'PopupMenuButton';
  }
  if (widget is mui.DropdownButton || widget is fmat.DropdownButton) {
    return 'DropdownButton';
  }
  if (widget is mui.MenuAnchor || widget is fmat.MenuAnchor) {
    return 'MenuAnchor';
  }
  if (widget is mui.SearchBar || widget is fmat.SearchBar) {
    return 'SearchBar';
  }
  if (widget is mui.TextFormField || widget is fmat.TextFormField) {
    return 'TextFormField';
  }
  if (widget is mui.TextField || widget is fmat.TextField) {
    return 'TextField';
  }
  if (widget is EditableText) return 'EditableText';
  if (widget is mui.SwitchListTile || widget is fmat.SwitchListTile) {
    return 'SwitchListTile';
  }
  if (widget is mui.CheckboxListTile || widget is fmat.CheckboxListTile) {
    return 'CheckboxListTile';
  }
  if (widget is mui.RadioListTile<Object?> ||
      widget is fmat.RadioListTile<Object?>) {
    return 'RadioListTile';
  }
  if (widget is mui.Switch || widget is fmat.Switch) return 'Switch';
  if (widget is cui.CupertinoSwitch || widget is fcup.CupertinoSwitch) {
    return 'CupertinoSwitch';
  }
  if (widget is mui.Checkbox || widget is fmat.Checkbox) return 'Checkbox';
  if (widget is mui.Radio<Object?> || widget is fmat.Radio<Object?>) {
    return 'Radio';
  }
  if (widget is mui.Slider || widget is fmat.Slider) return 'Slider';
  if (widget is cui.CupertinoSlider || widget is fcup.CupertinoSlider) {
    return 'CupertinoSlider';
  }
  if (widget is mui.ActionChip || widget is fmat.ActionChip) {
    return 'ActionChip';
  }
  if (widget is mui.FilterChip || widget is fmat.FilterChip) {
    return 'FilterChip';
  }
  if (widget is mui.ChoiceChip || widget is fmat.ChoiceChip) {
    return 'ChoiceChip';
  }
  if (widget is mui.InputChip || widget is fmat.InputChip) {
    return 'InputChip';
  }
  if (widget is mui.Chip ||
      widget is mui.RawChip ||
      widget is fmat.Chip ||
      widget is fmat.RawChip) {
    return 'Chip';
  }
  if (widget is mui.Card || widget is fmat.Card) return 'Card';
  if (widget is mui.ListTile || widget is fmat.ListTile) return 'ListTile';
  if (widget is mui.ExpansionTile || widget is fmat.ExpansionTile) {
    return 'ExpansionTile';
  }
  if (widget is mui.AppBar || widget is fmat.AppBar) return 'AppBar';
  if (widget is mui.SliverAppBar || widget is fmat.SliverAppBar) {
    return 'SliverAppBar';
  }
  if (widget is mui.NavigationBar || widget is fmat.NavigationBar) {
    return 'NavigationBar';
  }
  if (widget is mui.NavigationRail || widget is fmat.NavigationRail) {
    return 'NavigationRail';
  }
  if (widget is mui.NavigationDrawer || widget is fmat.NavigationDrawer) {
    return 'NavigationDrawer';
  }
  if (widget is mui.Drawer || widget is fmat.Drawer) return 'Drawer';
  if (widget is mui.BottomNavigationBar || widget is fmat.BottomNavigationBar) {
    return 'BottomNavigationBar';
  }
  if (widget is mui.TabBar || widget is fmat.TabBar) return 'TabBar';
  if (widget is mui.Tab || widget is fmat.Tab) return 'Tab';
  if (widget is mui.DataTable || widget is fmat.DataTable) return 'DataTable';
  if (widget is mui.Badge || widget is fmat.Badge) return 'Badge';
  if (widget is mui.Banner || widget is fmat.Banner) return 'Banner';
  if (widget is mui.Tooltip || widget is fmat.Tooltip) return 'Tooltip';
  if (widget is mui.AlertDialog || widget is fmat.AlertDialog) {
    return 'AlertDialog';
  }
  if (widget is mui.Dialog || widget is fmat.Dialog) return 'Dialog';
  if (widget is mui.BottomSheet || widget is fmat.BottomSheet) {
    return 'BottomSheet';
  }
  if (widget is mui.SelectableText || widget is fmat.SelectableText) {
    return 'SelectableText';
  }
  if (widget is Text) return 'Text';
  if (widget is RichText) return 'RichText';
  if (widget is Icon) return 'Icon';
  if (widget is Image) return 'Image';
  if (widget is ListView) return 'ListView';
  if (widget is GridView) return 'GridView';
  if (widget is CustomScrollView) return 'CustomScrollView';
  if (widget is SingleChildScrollView) return 'SingleChildScrollView';
  if (widget is mui.Scaffold || widget is fmat.Scaffold) return 'Scaffold';
  if (widget is cui.CupertinoPageScaffold ||
      widget is fcup.CupertinoPageScaffold) {
    return 'CupertinoPageScaffold';
  }
  if (widget is Container) return 'Container';
  if (widget is Semantics) return 'Semantics';

  final rawType = widget.runtimeType.toString().split('<').first;
  if (rawType.isEmpty ||
      rawType.startsWith('minified:') ||
      rawType.startsWith('_')) {
    return 'Widget';
  }
  return rawType;
}

_WidgetTier _classifyWidgetTier(
  Widget widget, {
  required bool hasUserLocation,
}) {
  // 1. Atomic interactive controls and leaf text/media targets.
  if (widget is mui.ButtonStyleButton ||
      widget is fmat.ButtonStyleButton ||
      widget is mui.IconButton ||
      widget is fmat.IconButton ||
      widget is mui.FloatingActionButton ||
      widget is fmat.FloatingActionButton ||
      widget is cui.CupertinoButton ||
      widget is fcup.CupertinoButton ||
      widget is mui.SegmentedButton<Object?> ||
      widget is fmat.SegmentedButton<Object?> ||
      widget is mui.PopupMenuButton ||
      widget is fmat.PopupMenuButton ||
      widget is mui.DropdownButton ||
      widget is fmat.DropdownButton ||
      widget is mui.SearchBar ||
      widget is fmat.SearchBar ||
      widget is mui.TextFormField ||
      widget is fmat.TextFormField ||
      widget is mui.TextField ||
      widget is fmat.TextField ||
      widget is EditableText ||
      widget is mui.Switch ||
      widget is fmat.Switch ||
      widget is cui.CupertinoSwitch ||
      widget is fcup.CupertinoSwitch ||
      widget is mui.Checkbox ||
      widget is fmat.Checkbox ||
      widget is mui.Radio<Object?> ||
      widget is fmat.Radio<Object?> ||
      widget is mui.Slider ||
      widget is fmat.Slider ||
      widget is cui.CupertinoSlider ||
      widget is fcup.CupertinoSlider ||
      widget is mui.Chip ||
      widget is mui.ActionChip ||
      widget is mui.FilterChip ||
      widget is mui.ChoiceChip ||
      widget is mui.InputChip ||
      widget is mui.RawChip ||
      widget is fmat.Chip ||
      widget is fmat.ActionChip ||
      widget is fmat.FilterChip ||
      widget is fmat.ChoiceChip ||
      widget is fmat.InputChip ||
      widget is fmat.RawChip ||
      widget is mui.SelectableText ||
      widget is fmat.SelectableText ||
      widget is Text ||
      widget is Icon ||
      widget is Image ||
      widget is RichText) {
    return _WidgetTier.atomic;
  }

  // 2. Top-level app/route plumbing and layout/focus/semantics wrappers.
  if (widget is mui.MaterialApp ||
      widget is fmat.MaterialApp ||
      widget is cui.CupertinoApp ||
      widget is fcup.CupertinoApp ||
      widget is WidgetsApp ||
      widget is Navigator ||
      widget is Overlay ||
      widget is ModalBarrier ||
      widget is Padding ||
      widget is Align ||
      widget is Center ||
      widget is SizedBox ||
      widget is ConstrainedBox ||
      widget is UnconstrainedBox ||
      widget is LimitedBox ||
      widget is FractionallySizedBox ||
      widget is IntrinsicHeight ||
      widget is IntrinsicWidth ||
      widget is FittedBox ||
      widget is AspectRatio ||
      widget is Baseline ||
      widget is Transform ||
      widget is RotatedBox ||
      widget is OverflowBox ||
      widget is Row ||
      widget is Column ||
      widget is Flex ||
      widget is Wrap ||
      widget is Stack ||
      widget is IndexedStack ||
      widget is Positioned ||
      widget is Expanded ||
      widget is Flexible ||
      widget is Spacer ||
      widget is CustomSingleChildLayout ||
      widget is CustomMultiChildLayout ||
      widget is LayoutBuilder ||
      widget is Builder ||
      widget is StatefulBuilder ||
      widget is MouseRegion ||
      widget is Listener ||
      widget is GestureDetector ||
      widget is RawGestureDetector ||
      widget is AbsorbPointer ||
      widget is IgnorePointer ||
      widget is MetaData ||
      widget is Focus ||
      widget is FocusScope ||
      widget is FocusableActionDetector ||
      widget is Actions ||
      widget is Shortcuts ||
      widget is MergeSemantics ||
      widget is BlockSemantics ||
      widget is ExcludeSemantics ||
      widget is IndexedSemantics ||
      widget is KeyedSubtree ||
      widget is RepaintBoundary ||
      widget is KeepAlive ||
      widget is AutomaticKeepAlive ||
      widget is NotificationListener ||
      widget is ScrollConfiguration ||
      widget is PrimaryScrollController ||
      widget is Hero ||
      widget is HeroControllerScope ||
      widget is TickerMode ||
      widget is Offstage ||
      widget is Visibility ||
      widget is Opacity ||
      widget is AnimatedOpacity ||
      widget is AnimatedSwitcher ||
      widget is AnimatedSize ||
      widget is AnimatedPadding ||
      widget is AnimatedAlign ||
      widget is MediaQuery ||
      widget is Directionality ||
      widget is DefaultTextStyle ||
      widget is AnimatedDefaultTextStyle ||
      widget is IconTheme ||
      widget is mui.Theme ||
      widget is fmat.Theme ||
      widget is mui.AnimatedTheme ||
      widget is fmat.AnimatedTheme ||
      widget is mui.Material ||
      widget is fmat.Material ||
      widget is PhysicalModel ||
      widget is PhysicalShape ||
      widget is DecoratedBox ||
      widget is ColoredBox ||
      widget is ClipRect ||
      widget is ClipRRect ||
      widget is ClipOval ||
      widget is ClipPath ||
      widget is mui.Ink ||
      widget is mui.InkWell ||
      widget is mui.InkResponse ||
      widget is fmat.Ink ||
      widget is fmat.InkWell ||
      widget is fmat.InkResponse ||
      widget is SafeArea ||
      widget is SliverToBoxAdapter ||
      widget is SliverPadding ||
      widget is Viewport ||
      widget is ShrinkWrappingViewport ||
      widget is Scrollable ||
      widget is ListView ||
      widget is GridView ||
      widget is CustomScrollView ||
      widget is SingleChildScrollView) {
    final explicitKey = extractFlutterWidgetKey(widget.key);
    if (explicitKey != null && hasUserLocation) {
      return _WidgetTier.meaningfulContainer;
    }
    return _WidgetTier.wrapper;
  }

  if (widget is Semantics) {
    final hasExplicitLabel =
        (widget.properties.label?.trim().isNotEmpty ?? false) ||
        (widget.properties.value?.trim().isNotEmpty ?? false) ||
        (widget.properties.tooltip?.trim().isNotEmpty ?? false);
    if (hasExplicitLabel && hasUserLocation) {
      return _WidgetTier.meaningfulContainer;
    }
    return _WidgetTier.wrapper;
  }

  // 3. Page-level fallback surfaces.
  if (widget is mui.Scaffold ||
      widget is fmat.Scaffold ||
      widget is cui.CupertinoPageScaffold ||
      widget is fcup.CupertinoPageScaffold) {
    return _WidgetTier.pageFallback;
  }

  // 4. Meaningful Material/Cupertino composite surfaces.
  if (widget is mui.Card ||
      widget is fmat.Card ||
      widget is mui.ListTile ||
      widget is fmat.ListTile ||
      widget is mui.SwitchListTile ||
      widget is fmat.SwitchListTile ||
      widget is mui.CheckboxListTile ||
      widget is fmat.CheckboxListTile ||
      widget is mui.RadioListTile<Object?> ||
      widget is fmat.RadioListTile<Object?> ||
      widget is mui.ExpansionTile ||
      widget is fmat.ExpansionTile ||
      widget is mui.AppBar ||
      widget is fmat.AppBar ||
      widget is mui.SliverAppBar ||
      widget is fmat.SliverAppBar ||
      widget is mui.NavigationBar ||
      widget is fmat.NavigationBar ||
      widget is mui.NavigationRail ||
      widget is fmat.NavigationRail ||
      widget is mui.NavigationDrawer ||
      widget is fmat.NavigationDrawer ||
      widget is mui.Drawer ||
      widget is fmat.Drawer ||
      widget is mui.BottomNavigationBar ||
      widget is fmat.BottomNavigationBar ||
      widget is mui.TabBar ||
      widget is fmat.TabBar ||
      widget is mui.Tab ||
      widget is fmat.Tab ||
      widget is mui.DataTable ||
      widget is fmat.DataTable ||
      widget is mui.Badge ||
      widget is fmat.Badge ||
      widget is mui.Banner ||
      widget is fmat.Banner ||
      widget is mui.Tooltip ||
      widget is fmat.Tooltip ||
      widget is mui.AlertDialog ||
      widget is fmat.AlertDialog ||
      widget is mui.Dialog ||
      widget is fmat.Dialog ||
      widget is mui.BottomSheet ||
      widget is fmat.BottomSheet) {
    return _WidgetTier.meaningfulContainer;
  }

  if (widget is Container) {
    final isDecorated = widget.decoration != null || widget.color != null;
    final hasExplicitKey = extractFlutterWidgetKey(widget.key) != null;
    if ((isDecorated || hasExplicitKey) && hasUserLocation) {
      return _WidgetTier.meaningfulContainer;
    }
    return _WidgetTier.wrapper;
  }

  // 5. Custom user StatelessWidget / StatefulWidget classes.
  final rawType = widget.runtimeType.toString();
  if (rawType.startsWith('_')) {
    return _WidgetTier.wrapper;
  }
  if (hasUserLocation &&
      (widget is StatelessWidget || widget is StatefulWidget)) {
    return _WidgetTier.meaningfulContainer;
  }
  if (extractFlutterWidgetKey(widget.key) != null) {
    return _WidgetTier.meaningfulContainer;
  }
  return _WidgetTier.wrapper;
}

bool _isCustomUserCompositeWidget(Widget widget) {
  if (widget is! StatelessWidget && widget is! StatefulWidget) {
    return false;
  }
  if (widget is mui.Card ||
      widget is fmat.Card ||
      widget is mui.ListTile ||
      widget is fmat.ListTile ||
      widget is mui.AppBar ||
      widget is fmat.AppBar ||
      widget is mui.Scaffold ||
      widget is fmat.Scaffold ||
      widget is Container) {
    return false;
  }
  final rawType = widget.runtimeType.toString();
  return !rawType.startsWith('_') && !rawType.startsWith('minified:');
}

bool _isHiddenSubtree(Element element, Widget widget) {
  if (widget is Offstage && widget.offstage) {
    return true;
  }
  if (widget is Visibility && !widget.visible) {
    return true;
  }
  if (widget is Opacity && widget.opacity <= 0.0) {
    return true;
  }
  if (widget is IgnorePointer && widget.ignoring) {
    return true;
  }
  final ro = element is RenderObjectElement ? element.renderObject : null;
  if (ro is RenderOffstage && ro.offstage) {
    return true;
  }
  if (ro is RenderOpacity && ro.opacity <= 0.0) {
    return true;
  }
  return false;
}

bool _isBlockingModalBarrier(Widget widget) => widget is ModalBarrier;

bool _clipsChildren(Element element, Widget widget) {
  if (widget is ClipRect ||
      widget is ClipRRect ||
      widget is ClipOval ||
      widget is ClipPath) {
    return true;
  }
  if (element is! RenderObjectElement) {
    return false;
  }
  final ro = element.renderObject;
  return ro is RenderClipRect ||
      ro is RenderClipRRect ||
      ro is RenderClipOval ||
      ro is RenderClipPath ||
      ro is RenderAbstractViewport;
}

List<Element> _collectOnstageChildren(Element element) {
  final children = <Element>[];
  element.debugVisitOnstageChildren(children.add);
  return children;
}

RenderBox? _renderBoxIfReady(Element element) {
  final ro = element.renderObject;
  if (ro is RenderBox && ro.attached && ro.hasSize) {
    return ro;
  }
  return null;
}

Rect? _globalBoundsOf(RenderBox box) {
  try {
    final topLeft = box.localToGlobal(Offset.zero);
    final bottomRight = box.localToGlobal(
      Offset(box.size.width, box.size.height),
    );
    if (!topLeft.dx.isFinite ||
        !topLeft.dy.isFinite ||
        !bottomRight.dx.isFinite ||
        !bottomRight.dy.isFinite) {
      return null;
    }
    return Rect.fromPoints(topLeft, bottomRight);
  } on Object {
    return null;
  }
}

bool _sameBoundsApproximately(Rect a, Rect b, {double tolerance = 2.0}) =>
    (a.left - b.left).abs() <= tolerance &&
    (a.top - b.top).abs() <= tolerance &&
    (a.width - b.width).abs() <= tolerance &&
    (a.height - b.height).abs() <= tolerance;

bool _containsRectApproximately(
  Rect outer,
  Rect inner, {
  double tolerance = 4.0,
}) =>
    outer.left <= inner.left + tolerance &&
    outer.top <= inner.top + tolerance &&
    outer.right >= inner.right - tolerance &&
    outer.bottom >= inner.bottom - tolerance;

bool _shouldPreferEnclosing(_EvaluatedHit candidate, _EvaluatedHit current) {
  final candidateHasLoc =
      candidate.directLocation != null || candidate.nearestUserLocation != null;
  final currentHasLoc =
      current.directLocation != null || current.nearestUserLocation != null;
  if (candidateHasLoc && !currentHasLoc) {
    return true;
  }
  if (!candidateHasLoc && currentHasLoc) {
    return false;
  }
  final candidateArea = candidate.bounds.width * candidate.bounds.height;
  final currentArea = current.bounds.width * current.bounds.height;
  return candidateArea <= currentArea + 1.0;
}

bool _isCloseWrapperLocation(_EvaluatedHit hit) =>
    hit.directLocation == null &&
    hit.nearestUserLocation != null &&
    hit.tier == _WidgetTier.meaningfulContainer;

String _collectSpecificDescendantWidgetText(Element root, Widget targetWidget) {
  String? found;
  void search(Element element) {
    if (found != null || !element.mounted || element.debugIsDefunct) {
      return;
    }
    if (identical(element.widget, targetWidget)) {
      found = collectVisibleText(element);
      return;
    }
    for (final child in _collectOnstageChildren(element)) {
      search(child);
    }
  }

  search(root);
  return found ?? '';
}

// Strip Unicode Private Use Area icon-font glyphs (U+E000..U+F8FF and
// Plane 15/16 supplementary PUA surrogates) before normalizing whitespace.
final RegExp _iconGlyphRegex = RegExp(
  r'[\uE000-\uF8FF]|[\uDB80-\uDBFF][\uDC00-\uDFFF]',
);

String _normalizeWhitespace(String input) => input
    .replaceAll(_iconGlyphRegex, '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

String _capText(String text, {int maxLength = _maxExtractedTextLength}) {
  if (text.length <= maxLength) {
    return text;
  }
  return '${text.substring(0, maxLength - 3).trimRight()}...';
}

String _joinAndCapSegments(List<String> segments) {
  if (segments.isEmpty) {
    return '';
  }
  final nonEmpty = segments
      .map(_normalizeWhitespace)
      .where((s) => s.isNotEmpty)
      .toList();
  if (nonEmpty.isEmpty) {
    return '';
  }
  return _capText(nonEmpty.join(' '));
}

double _roundPct(double value) {
  if (!value.isFinite) {
    return 0;
  }
  final clamped = value.clamp(0.0, 100.0);
  return (clamped * 1000).roundToDouble() / 1000;
}
