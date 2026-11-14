// Copyright (c) 2026, Abdallah Shaban. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:review_comments/review_comments.dart';
import 'package:web/web.dart' as web;

import 'config.dart';
import 'navigator_observer.dart';
import 'widget_inspector_bridge.dart';

const bool _kProductionDefine =
    bool.fromEnvironment('PRODUCTION') ||
    bool.fromEnvironment('REVIEW_COMMENTS_PRODUCTION');

const String _kEnvReviewMode = String.fromEnvironment('REVIEW_COMMENTS_MODE');
const String _kEnvDashMode = String.fromEnvironment('DASH_REVIEW_MODE');
const String _kEffectiveEnvMode = _kEnvReviewMode != ''
    ? _kEnvReviewMode
    : _kEnvDashMode;

/// Compile-time guard allowing `dart2js` / `dart2wasm` to tree-shake the entire
/// client script, CSS bundle, and inspector bridge out of plain production
/// `flutter build web` builds when no explicit review mode define is set.
const bool _kWebOverlayCompiledIn =
    !_kProductionDefine &&
    (!kReleaseMode ||
        _kEffectiveEnvMode == 'local' ||
        _kEffectiveEnvMode == 'preview');

/// Wraps a Flutter Web application or subtree to bridge Flutter's live
/// [Element] / [RenderBox] widget tree into the Shadow-DOM review overlay.
///
/// Automatically disables itself with zero runtime or bundle overhead in plain
/// release builds (`flutter build web` without `REVIEW_COMMENTS_MODE`) and
/// whenever `PRODUCTION=true` is set.
class ReviewCommentsOverlay extends StatelessWidget {
  /// Creates a [ReviewCommentsOverlay] widget.
  const ReviewCommentsOverlay({
    super.key,
    required this.child,
    this.config = const ReviewCommentsConfig(),
    this.navigatorObserver,
    this.enabled,
  });

  /// The application or page subtree to inspect.
  final Widget child;

  /// Configuration and safety-gate settings for the review overlay.
  final ReviewCommentsConfig config;

  /// Optional [ReviewCommentsNavigatorObserver] passed to `MaterialApp`.
  final ReviewCommentsNavigatorObserver? navigatorObserver;

  /// Optional shorthand override for [ReviewCommentsConfig.enabled].
  final bool? enabled;

  @override
  Widget build(BuildContext context) {
    if (!_kWebOverlayCompiledIn) {
      return child;
    }
    return _ActiveWebReviewOverlay(
      config: enabled == null
          ? config
          : ReviewCommentsConfig(
              mode: config.mode,
              enabled: enabled,
              enableInDebug: config.enableInDebug,
              isProduction: config.isProduction,
              isReleaseMode: config.isReleaseMode,
              site: config.site,
              serverPort: config.serverPort,
              prNumber: config.prNumber,
              repo: config.repo,
              commitSha: config.commitSha,
              headBranch: config.headBranch,
              defaultSourceFile: config.defaultSourceFile,
              routeSourceFiles: config.routeSourceFiles,
              feedbackFile: config.feedbackFile,
              cliResolveCommand: config.cliResolveCommand,
            ),
      navigatorObserver: navigatorObserver,
      child: child,
    );
  }
}

class _ActiveWebReviewOverlay extends StatefulWidget {
  const _ActiveWebReviewOverlay({
    required this.child,
    required this.config,
    this.navigatorObserver,
  });

  final Widget child;
  final ReviewCommentsConfig config;
  final ReviewCommentsNavigatorObserver? navigatorObserver;

  @override
  State<_ActiveWebReviewOverlay> createState() =>
      _ActiveWebReviewOverlayState();
}

class _ActiveWebReviewOverlayState extends State<_ActiveWebReviewOverlay>
    with WidgetsBindingObserver {
  final GlobalKey _subtreeKey = GlobalKey(debugLabel: 'ReviewCommentsSubtree');
  late FlutterWidgetTreeInspector _inspector;
  String _lastKnownRoute = '';
  Timer? _settleTimer;

  @override
  void initState() {
    super.initState();
    _inspector = _createInspector();
    if (widget.config.isEnabled) {
      WidgetsBinding.instance.addObserver(this);
      widget.navigatorObserver?.addListener(_onRouteMaybeChanged);
      _mountWebOverlayAndAdapter();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _syncConfigAndNotifyNavigation();
        }
      });
    }
  }

  @override
  void didUpdateWidget(covariant _ActiveWebReviewOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.navigatorObserver != widget.navigatorObserver) {
      oldWidget.navigatorObserver?.removeListener(_onRouteMaybeChanged);
      if (widget.config.isEnabled) {
        widget.navigatorObserver?.addListener(_onRouteMaybeChanged);
      }
    }
    _inspector = _createInspector();
    if (!oldWidget.config.isEnabled && widget.config.isEnabled) {
      WidgetsBinding.instance.addObserver(this);
      widget.navigatorObserver?.addListener(_onRouteMaybeChanged);
      _mountWebOverlayAndAdapter();
    } else if (oldWidget.config.isEnabled && !widget.config.isEnabled) {
      WidgetsBinding.instance.removeObserver(this);
      widget.navigatorObserver?.removeListener(_onRouteMaybeChanged);
      _unmountAdapter();
    } else if (widget.config.isEnabled) {
      _mountWebOverlayAndAdapter();
      _syncConfigAndNotifyNavigation();
    }
  }

  @override
  void dispose() {
    _settleTimer?.cancel();
    if (widget.config.isEnabled) {
      WidgetsBinding.instance.removeObserver(this);
      widget.navigatorObserver?.removeListener(_onRouteMaybeChanged);
      _unmountAdapter();
    }
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    _dispatchScrollGeometryRefresh();
  }

  @override
  Future<bool> didPushRouteInformation(
    RouteInformation routeInformation,
  ) async {
    _onRouteMaybeChanged();
    return false;
  }

  @override
  Future<bool> didPopRoute() async {
    _onRouteMaybeChanged();
    return false;
  }

  FlutterWidgetTreeInspector _createInspector() => FlutterWidgetTreeInspector(
    rootKey: _subtreeKey,
    config: widget.config,
    navigatorObserver: widget.navigatorObserver,
    fallbackRouteReader: _readBrowserRoute,
    fallbackTitleReader: () => web.document.title,
  );

  String _readBrowserRoute() {
    final loc = web.window.location;
    final hash = loc.hash;
    if (hash.startsWith('#/') || hash.startsWith('#')) {
      final candidate = normalizeFlutterRoutePath(hash);
      if (candidate != '/' || loc.pathname.isEmpty || loc.pathname == '/') {
        return candidate;
      }
    }
    return normalizeFlutterRoutePath(loc.pathname);
  }

  Offset _flutterViewOffset() {
    final viewEl = web.document.querySelector('flutter-view');
    if (viewEl == null) {
      return Offset.zero;
    }
    final rect = viewEl.getBoundingClientRect();
    return Offset(rect.left, rect.top);
  }

  Size _viewportSize() =>
      Size(web.window.innerWidth.toDouble(), web.window.innerHeight.toDouble());

  void _onRouteMaybeChanged() {
    if (!mounted || !widget.config.isEnabled) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _syncConfigAndNotifyNavigation();
      // Re-sync once route transition animations settle (~350ms) so live widget
      // pin coordinates reflect the final resting layout.
      _settleTimer?.cancel();
      _settleTimer = Timer(const Duration(milliseconds: 360), () {
        if (mounted) {
          _syncConfigAndNotifyNavigation();
        }
      });
    });
  }

  void _syncConfigAndNotifyNavigation() {
    final ctx = _inspector.getPageContext();
    _writeConfigElement(ctx);
    final routeChanged = ctx.pageUrl != _lastKnownRoute;
    _lastKnownRoute = ctx.pageUrl;
    if (routeChanged) {
      _callWindowHook('__reviewCommentsNotifyNavigation');
    } else {
      _dispatchScrollGeometryRefresh();
    }
  }

  void _dispatchScrollGeometryRefresh() {
    try {
      web.window.dispatchEvent(web.Event('scroll'));
    } on Object {
      // Ignore synthetic event errors in headless/stubbed environments.
    }
  }

  void _mountWebOverlayAndAdapter() {
    final win = web.window as JSObject;
    win['__REVIEW_COMMENTS_ADAPTER__'] = _buildJsAdapter();

    final head = web.document.head ?? web.document.documentElement;
    if (head != null && web.document.getElementById(stylesElementId) == null) {
      final styleEl =
          web.document.createElement('style') as web.HTMLStyleElement
            ..id = stylesElementId
            ..textContent = reviewOverlayStyles;
      styleEl.setAttribute('data-dash-review-ignore', 'true');
      head.appendChild(styleEl);
    }

    final initialCtx = _inspector.getPageContext();
    _lastKnownRoute = initialCtx.pageUrl;
    _writeConfigElement(initialCtx);

    final alreadyBootstrapped =
        win['__reviewCommentsBootstrapped'] == true.toJS ||
        web.document.getElementById(scriptElementId) != null;
    if (!alreadyBootstrapped) {
      final scriptParent =
          web.document.body ??
          web.document.head ??
          web.document.documentElement;
      if (scriptParent != null) {
        final scriptEl =
            web.document.createElement('script') as web.HTMLScriptElement
              ..id = scriptElementId
              ..text = reviewOverlayClientScript;
        scriptEl.setAttribute('data-dash-review-ignore', 'true');
        scriptParent.appendChild(scriptEl);
      }
    } else {
      _callWindowHook('__reviewCommentsNotifyNavigation');
      _callWindowHook('__reviewCommentsRefresh');
    }
  }

  void _writeConfigElement(FlutterPageContext pageContext) {
    final coreConfig = widget.config.toCoreConfig();
    final map = coreConfig.toPageConfigMap(
      pageUrl: pageContext.pageUrl,
      pageTitle: pageContext.pageTitle,
      sourceFile: pageContext.sourceFile,
      defaultSite: 'app',
    );
    final encoded = encodeReviewJsonForHtml(map);
    final existing = web.document.getElementById(configElementId);
    if (existing != null) {
      existing.textContent = encoded;
      return;
    }
    final parent =
        web.document.head ?? web.document.body ?? web.document.documentElement;
    if (parent == null) {
      return;
    }
    final configScript =
        web.document.createElement('script') as web.HTMLScriptElement
          ..id = configElementId
          ..type = 'application/json'
          ..textContent = encoded;
    configScript.setAttribute('data-dash-review-ignore', 'true');
    parent.appendChild(configScript);
  }

  void _unmountAdapter() {
    final win = web.window as JSObject;
    win['__REVIEW_COMMENTS_ADAPTER__'] = null;
  }

  void _callWindowHook(String methodName) {
    final win = web.window as JSObject;
    final fn = win[methodName];
    if (fn != null && !fn.isUndefinedOrNull && fn.typeofEquals('function')) {
      try {
        (fn as JSFunction).callAsFunction(win);
      } on Object {
        // Ignore hook errors from external JS overrides.
      }
    }
  }

  JSObject _buildJsAdapter() {
    final adapter = JSObject();
    adapter['getPageContext'] = (() => _jsGetPageContext()).toJS;
    adapter['inspectPoint'] =
        ((JSNumber clientX, JSNumber clientY) => _jsInspectPoint(
          clientX.toDartDouble,
          clientY.toDartDouble,
        )).toJS;
    adapter['inspectArea'] = ((JSObject rawArea) => _jsInspectArea(
      rawArea,
    )).toJS;
    adapter['locateCommentRect'] =
        ((JSObject rawRecord) => _jsLocateCommentRect(rawRecord)).toJS;
    adapter['navigateTo'] = ((JSString rawRoute) => _jsNavigateTo(
      rawRoute.toDart,
    )).toJS;
    return adapter;
  }

  JSObject _jsGetPageContext() {
    final ctx = _inspector.getPageContext();
    final obj = JSObject();
    obj['pageUrl'] = ctx.pageUrl.toJS;
    obj['pageTitle'] = ctx.pageTitle.toJS;
    obj['sourceFile'] = ctx.sourceFile.toJS;
    return obj;
  }

  JSObject? _jsInspectPoint(double clientX, double clientY) {
    if (!clientX.isFinite || !clientY.isFinite) {
      return null;
    }
    final hit = _inspector.inspectPoint(
      Offset(clientX, clientY),
      viewOffset: _flutterViewOffset(),
    );
    if (hit == null) {
      return null;
    }
    final rectObj = _rectToJs(hit.rect);
    final obj = JSObject();
    obj['rect'] = rectObj;
    obj['label'] = hit.label.toJS;
    obj['elementTag'] = hit.elementTag.toJS;
    obj['selector'] = hit.selector.toJS;
    obj['selectedText'] = hit.selectedText.toJS;
    obj['elementText'] = hit.elementText.toJS;
    obj['headingAnchor'] = hit.headingAnchor.toJS;
    obj['sourceFile'] = hit.sourceFile.toJS;
    obj['startLine'] = hit.startLine?.toJS;
    obj['endLine'] = hit.endLine?.toJS;
    return obj;
  }

  JSObject? _jsInspectArea(JSObject rawArea) {
    final left = _readJsDouble(rawArea, 'left');
    final top = _readJsDouble(rawArea, 'top');
    final width = _readJsDouble(rawArea, 'width');
    final height = _readJsDouble(rawArea, 'height');
    if (left == null || top == null || width == null || height == null) {
      return null;
    }
    final area = _inspector.inspectArea(
      Rect.fromLTWH(left, top, width, height),
      viewportSize: _viewportSize(),
      viewOffset: _flutterViewOffset(),
    );
    if (area == null) {
      return null;
    }
    final rectPctObj = JSObject();
    rectPctObj['x'] = (area.rectPct['x'] ?? 0).toJS;
    rectPctObj['y'] = (area.rectPct['y'] ?? 0).toJS;
    rectPctObj['w'] = (area.rectPct['w'] ?? 100).toJS;
    rectPctObj['h'] = (area.rectPct['h'] ?? 100).toJS;

    final obj = JSObject();
    obj['elementTag'] = area.elementTag.toJS;
    obj['selector'] = area.selector.toJS;
    obj['selectedText'] = area.selectedText.toJS;
    obj['elementText'] = area.elementText.toJS;
    obj['sourceFile'] = area.sourceFile.toJS;
    obj['startLine'] = area.startLine?.toJS;
    obj['endLine'] = area.endLine?.toJS;
    obj['rectPct'] = rectPctObj;
    return obj;
  }

  JSObject? _jsLocateCommentRect(JSObject rawRecord) {
    final selector = _readJsString(rawRecord, 'selector');
    if (selector.isEmpty) {
      return null;
    }
    final anchorType = _readJsString(
      rawRecord,
      'anchorType',
      fallback: 'element',
    );
    final elementText = _readJsString(rawRecord, 'elementText');
    final selectedText = _readJsString(rawRecord, 'selectedText');
    final startLineNum = _readJsDouble(rawRecord, 'startLine');
    final located = _inspector.locateCommentRect(
      selector: selector,
      anchorType: anchorType,
      elementText: elementText,
      selectedText: selectedText,
      startLine: startLineNum?.round(),
      viewOffset: _flutterViewOffset(),
    );
    if (located == null) {
      return null;
    }
    return _rectToJs(located);
  }

  void _jsNavigateTo(String rawRoute) {
    final target = normalizeFlutterRoutePath(rawRoute);
    final nav = widget.navigatorObserver?.navigator;
    if (nav != null) {
      if (target == '/') {
        nav.popUntil((route) => route.isFirst);
      } else {
        unawaited(nav.pushNamed(target));
      }
      _onRouteMaybeChanged();
      return;
    }
    web.window.location.hash = target == '/' ? '#/' : '#$target';
    _onRouteMaybeChanged();
  }

  JSObject _rectToJs(FlutterLocatedRect rect) {
    final obj = JSObject();
    obj['left'] = rect.left.toJS;
    obj['top'] = rect.top.toJS;
    obj['width'] = rect.width.toJS;
    obj['height'] = rect.height.toJS;
    return obj;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.config.isEnabled) {
      return widget.child;
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        _dispatchScrollGeometryRefresh();
        return false;
      },
      child: KeyedSubtree(key: _subtreeKey, child: widget.child),
    );
  }
}

double? _readJsDouble(JSObject obj, String key) {
  final val = obj[key];
  if (val == null || val.isUndefinedOrNull) {
    return null;
  }
  if (val.typeofEquals('number')) {
    final number = (val as JSNumber).toDartDouble;
    return number.isFinite ? number : null;
  }
  return null;
}

String _readJsString(JSObject obj, String key, {String fallback = ''}) {
  final val = obj[key];
  if (val == null || val.isUndefinedOrNull) {
    return fallback;
  }
  if (val.typeofEquals('string')) {
    return (val as JSString).toDart;
  }
  return fallback;
}
