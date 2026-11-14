// Copyright (c) 2026, Abdallah Shaban. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:material_ui/material_ui.dart';
import 'package:review_comments_flutter/review_comments_flutter.dart';

final ReviewCommentsNavigatorObserver _reviewNavigatorObserver =
    ReviewCommentsNavigatorObserver();

void main() {
  runApp(const FlutterReviewDemoApp());
}

/// Demo Flutter Web application wrapped in [ReviewCommentsOverlay].
class FlutterReviewDemoApp extends StatelessWidget {
  /// Creates the demo application.
  const FlutterReviewDemoApp({super.key, this.navigatorObserver});

  /// Optional observer override for widget tests.
  final ReviewCommentsNavigatorObserver? navigatorObserver;

  @override
  Widget build(BuildContext context) {
    final observer = navigatorObserver ?? _reviewNavigatorObserver;
    return ReviewCommentsOverlay(
      navigatorObserver: observer,
      config: const ReviewCommentsConfig(
        site: 'flutter_web_example',
        defaultSourceFile: 'lib/main.dart',
        routeSourceFiles: <String, String>{
          '/': 'lib/main.dart',
          '/details': 'lib/main.dart',
        },
      ),
      child: MaterialApp(
        title: 'Flutter Web Release Dashboard',
        debugShowCheckedModeBanner: false,
        navigatorObservers: <NavigatorObserver>[observer],
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF2563EB),
            brightness: Brightness.light,
          ),
        ),
        initialRoute: '/',
        routes: <String, WidgetBuilder>{
          '/': (context) => const DashboardScreen(),
          '/details': (context) => const FeatureDetailsScreen(),
        },
      ),
    );
  }
}

/// Primary `/` route displaying release metrics, cards, and action buttons.
class DashboardScreen extends StatefulWidget {
  /// Creates the dashboard screen.
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _smokeCheckVerified = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: const Text('Flutter Web Release Dashboard'),
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: TextButton.icon(
              key: const ValueKey<String>('appbar-details-btn'),
              onPressed: () => Navigator.pushNamed(context, '/details'),
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('Feature Details'),
            ),
          ),
        ],
      ),
      body: ListView(
        key: const ValueKey<String>('dashboard-scroll-view'),
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        children: <Widget>[
          Card(
            key: const ValueKey<String>('hero-release-card'),
            elevation: 0,
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Release v3.50 Rollout Overview',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Highlight any Flutter widget or drag an area in Comment '
                    'Mode (Alt+C) to sync source-mapped feedback to local '
                    'coding agents or GitHub PR diffs.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF475569),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: <Widget>[
                      FilledButton.icon(
                        key: const ValueKey<String>('open-details-btn'),
                        onPressed: () =>
                            Navigator.pushNamed(context, '/details'),
                        icon: const Icon(Icons.analytics_outlined, size: 18),
                        label: const Text('Inspect Feature Details'),
                      ),
                      OutlinedButton.icon(
                        key: const ValueKey<String>('run-smoke-check-btn'),
                        onPressed: () {
                          setState(() {
                            _smokeCheckVerified = !_smokeCheckVerified;
                          });
                        },
                        icon: Icon(
                          _smokeCheckVerified
                              ? Icons.verified_outlined
                              : Icons.play_arrow_rounded,
                          size: 18,
                        ),
                        label: Text(
                          _smokeCheckVerified
                              ? 'Smoke Check Verified'
                              : 'Run Smoke Check',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Live Telemetry Metrics',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 12),
          const Wrap(
            spacing: 16,
            runSpacing: 16,
            children: <Widget>[
              MetricSummaryTile(
                key: ValueKey<String>('metric-sessions'),
                label: 'Active Web Sessions',
                value: '12,480',
                delta: '+14.2% vs last release',
                icon: Icons.public,
              ),
              MetricSummaryTile(
                key: ValueKey<String>('metric-frame-time'),
                label: 'P95 Raster Time',
                value: '4.8 ms',
                delta: 'Within 16.6 ms budget',
                icon: Icons.speed,
              ),
              MetricSummaryTile(
                key: ValueKey<String>('metric-builds'),
                label: 'Verified PR Previews',
                value: '1,284',
                delta: '99.98% pass rate',
                icon: Icons.check_circle_outline,
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            'Pre-Launch Verification Gates',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            key: const ValueKey<String>('checklist-card'),
            elevation: 0,
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            child: const Column(
              children: <Widget>[
                ListTile(
                  key: ValueKey<String>('gate-canvaskit'),
                  leading: Icon(
                    Icons.layers_outlined,
                    color: Color(0xFF2563EB),
                  ),
                  title: Text('CanvasKit & Skwasm Hit-Test Parity'),
                  subtitle: Text(
                    'Maps viewport pointer coordinates to live RenderBox bounds.',
                  ),
                ),
                Divider(height: 1),
                ListTile(
                  key: ValueKey<String>('gate-production'),
                  leading: Icon(
                    Icons.shield_outlined,
                    color: Color(0xFF059669),
                  ),
                  title: Text('Zero-Byte Production Release Gate'),
                  subtitle: Text(
                    'Tree-shakes overlay script and styles when mode is unset.',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Reusable metric summary card displayed on the dashboard.
class MetricSummaryTile extends StatelessWidget {
  /// Creates a [MetricSummaryTile].
  const MetricSummaryTile({
    super.key,
    required this.label,
    required this.value,
    required this.delta,
    required this.icon,
  });

  /// Metric title label.
  final String label;

  /// Comma-formatted primary metric figure.
  final String value;

  /// Supporting comparison caption.
  final String delta;

  /// Leading telemetry icon.
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 280,
      child: Card(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(icon, size: 18, color: const Color(0xFF2563EB)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: const Color(0xFF475569),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                value,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                delta,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF059669),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Secondary `/details` route demonstrating route-scoped review pins.
class FeatureDetailsScreen extends StatefulWidget {
  /// Creates the feature details screen.
  const FeatureDetailsScreen({super.key});

  @override
  State<FeatureDetailsScreen> createState() => _FeatureDetailsScreenState();
}

class _FeatureDetailsScreenState extends State<FeatureDetailsScreen> {
  bool _canaryEnabled = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: const Text('Feature Details'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        children: <Widget>[
          Card(
            key: const ValueKey<String>('feature-architecture-card'),
            elevation: 0,
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Shadow-DOM & Flutter Element Inspector Bridge',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 10),
                  RichText(
                    text: TextSpan(
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF334155),
                      ),
                      text: 'Active Route Diagnostic: ',
                      children: const <InlineSpan>[
                        TextSpan(
                          text:
                              'Pins anchored on /details stay scoped to /details.',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  const SelectableText('Build Artifact: skwasm-canary-9,412'),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    key: const ValueKey<String>('canary-rollout-switch'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Enable Skwasm Canary Cohort'),
                    subtitle: const Text(
                      'Currently serving 2,500 preview users',
                    ),
                    value: _canaryEnabled,
                    onChanged: (val) => setState(() => _canaryEnabled = val),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    key: const ValueKey<String>('back-to-dashboard-btn'),
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back, size: 18),
                    label: const Text('Return to Dashboard'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
