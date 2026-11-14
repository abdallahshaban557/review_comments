// Copyright (c) 2026, Abdallah Shaban. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// First-class visual highlight, local coding-agent feedback, and GitHub PR
/// diff comment overlay for Flutter Web apps.
///
/// Uses conditional multi-platform exports so non-web Flutter targets (iOS,
/// Android, macOS, Windows, Linux, and VM `flutter test`) compile cleanly with
/// zero web dependencies and zero runtime overhead.
library;

export 'package:review_comments/review_comments.dart' show ReviewConfig;

export 'src/config.dart' show ReviewCommentsConfig, normalizeFlutterRoutePath;
export 'src/navigator_observer.dart' show ReviewCommentsNavigatorObserver;
export 'src/overlay_stub.dart'
    if (dart.library.js_interop) 'src/overlay_web.dart'
    show ReviewCommentsOverlay;
export 'src/widget_inspector_bridge.dart'
    show
        FlutterInspectedArea,
        FlutterInspectedPoint,
        FlutterLocatedRect,
        FlutterPageContext,
        FlutterWidgetTreeInspector,
        WidgetSourceLocation,
        collectVisibleText,
        collectVisibleTextSegments,
        describeFlutterWidgetType,
        extractFlutterWidgetKey,
        extractWidgetSourceLocation,
        formatFlutterSelector,
        isFrameworkOrExternalCreationUri,
        normalizeWidgetSourceFile,
        parseFlutterSelector;
