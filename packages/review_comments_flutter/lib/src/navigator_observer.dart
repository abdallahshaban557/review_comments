// Copyright (c) 2026, Abdallah Shaban. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/widgets.dart';

import 'config.dart';

/// A [NavigatorObserver] that tracks the active Flutter route and notifies
/// `ReviewCommentsOverlay` whenever navigation occurs.
///
/// Pass an instance to `MaterialApp.navigatorObservers` (or `Navigator.observers`)
/// and to `ReviewCommentsOverlay(navigatorObserver: ...)` so route transitions
/// automatically refresh active page pins and drawer filters.
class ReviewCommentsNavigatorObserver extends NavigatorObserver
    implements Listenable {
  final List<VoidCallback> _listeners = <VoidCallback>[];
  final List<Route<dynamic>> _routeStack = <Route<dynamic>>[];
  String? _currentRoute;

  /// The normalized path of the currently active named route, or `null` if no
  /// named route has been observed yet.
  String? get currentRoute => _currentRoute;

  /// The raw title or route name for display when available.
  String? get currentRouteTitle {
    for (var i = _routeStack.length - 1; i >= 0; i--) {
      final name = _routeStack[i].settings.name;
      if (name != null && name.trim().isNotEmpty) {
        return name.trim();
      }
    }
    return _currentRoute;
  }

  @override
  void addListener(VoidCallback listener) {
    _listeners.add(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  void _notify() {
    for (final listener in List<VoidCallback>.of(_listeners)) {
      listener();
    }
  }

  void _syncTopRoute([Route<dynamic>? fallbackCandidate]) {
    String? resolved;
    for (var i = _routeStack.length - 1; i >= 0; i--) {
      final name = _routeStack[i].settings.name;
      if (name != null && name.trim().isNotEmpty) {
        resolved = normalizeFlutterRoutePath(name);
        break;
      }
    }
    if (resolved == null && fallbackCandidate != null) {
      final fallbackName = fallbackCandidate.settings.name;
      if (fallbackName != null && fallbackName.trim().isNotEmpty) {
        resolved = normalizeFlutterRoutePath(fallbackName);
      }
    }
    if (resolved != null) {
      _currentRoute = resolved;
    }
    _notify();
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    if (previousRoute != null && !_routeStack.contains(previousRoute)) {
      _routeStack.add(previousRoute);
    }
    _routeStack.remove(route);
    _routeStack.add(route);
    _syncTopRoute(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    _routeStack.remove(route);
    if (previousRoute != null && !_routeStack.contains(previousRoute)) {
      _routeStack.add(previousRoute);
    }
    _syncTopRoute(previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    if (oldRoute != null) {
      final idx = _routeStack.indexOf(oldRoute);
      if (idx != -1) {
        if (newRoute != null) {
          _routeStack[idx] = newRoute;
        } else {
          _routeStack.removeAt(idx);
        }
      } else if (newRoute != null) {
        _routeStack.add(newRoute);
      }
    } else if (newRoute != null) {
      _routeStack.add(newRoute);
    }
    _syncTopRoute(newRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    _routeStack.remove(route);
    _syncTopRoute(previousRoute);
  }
}
