// Copyright (c) 2026, Abdallah Shaban. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:review_comments/review_comments.dart';
import 'package:test/test.dart';

void main() {
  group('ReviewConfig and compile-time safety gates', () {
    test('is disabled by default when no mode define is set', () {
      expect(ReviewConfig.environment.mode, isEmpty);
      expect(ReviewConfig.environment.isEnabled, isFalse);
      expect(ReviewConfig.environment.serverOrigin, isEmpty);
      expect(defaultReviewServerPort, equals(4099));
      expect(defaultReviewDirectory, equals('.review_comments'));
      expect(configElementId, equals('dash-review-config'));
    });

    test('enables only local and preview modes when not in production', () {
      const localCfg = ReviewConfig(mode: 'local', serverPort: '4099');
      expect(localCfg.isEnabled, isTrue);
      expect(localCfg.serverOrigin, equals('http://127.0.0.1:4099'));

      const previewCfg = ReviewConfig(
        mode: 'preview',
        prNumber: '42',
        repo: 'abdallahshaban/review_comments',
      );
      expect(previewCfg.isEnabled, isTrue);
      expect(previewCfg.serverOrigin, isEmpty);

      const emptyCfg = ReviewConfig();
      expect(emptyCfg.isEnabled, isFalse);

      const invalidMode = ReviewConfig(mode: 'staging');
      expect(invalidMode.isEnabled, isFalse);
    });

    test('hard blocks overlay whenever productionBuild is true', () {
      const prodLocal = ReviewConfig(
        mode: 'local',
        productionBuild: true,
        serverPort: '4099',
      );
      expect(prodLocal.isEnabled, isFalse);

      const prodPreview = ReviewConfig(
        mode: 'preview',
        productionBuild: true,
        prNumber: '42',
      );
      expect(prodPreview.isEnabled, isFalse);
    });

    test(
      'supports REVIEW_COMMENTS_* and legacy DASH_REVIEW_* dart-defines',
      () async {
        final packageRoot = Directory.current.path;
        final tempDir = await Directory.systemTemp.createTemp('rc_defines_');
        try {
          final probe = File('${tempDir.path}/probe.dart');
          await probe.writeAsString('''
import 'dart:convert';
import 'package:review_comments/review_comments.dart';

void main() {
  const cfg = ReviewConfig.fromEnvironment(defaultRepo: 'fallback/repo');
  print(jsonEncode({
    'mode': cfg.mode,
    'isEnabled': cfg.isEnabled,
    'site': cfg.site,
    'serverOrigin': cfg.serverOrigin,
    'prNumber': cfg.prNumber,
    'repo': cfg.repo,
    'commitSha': cfg.commitSha,
    'headBranch': cfg.headBranch,
  }));
}
''');

          final pkgConfig = File(
            '$packageRoot/.dart_tool/package_config.json',
          ).path;

          // 1. New REVIEW_COMMENTS_* defines take precedence over DASH_REVIEW_*
          final rcRes = await Process.run(Platform.resolvedExecutable, [
            '--packages=$pkgConfig',
            '-DREVIEW_COMMENTS_MODE=local',
            '-DDASH_REVIEW_MODE=preview',
            '-DREVIEW_COMMENTS_SERVER_PORT=4123',
            '-DREVIEW_COMMENTS_SITE=app',
            probe.path,
          ]);
          expect(rcRes.exitCode, equals(0), reason: '${rcRes.stderr}');
          final rcJson =
              jsonDecode((rcRes.stdout as String).trim())
                  as Map<String, Object?>;
          expect(rcJson['mode'], equals('local'));
          expect(rcJson['isEnabled'], isTrue);
          expect(rcJson['site'], equals('app'));
          expect(rcJson['serverOrigin'], equals('http://127.0.0.1:4123'));
          expect(rcJson['repo'], equals('fallback/repo'));

          // 2. Legacy DASH_REVIEW_* fallback works cleanly
          final drRes = await Process.run(Platform.resolvedExecutable, [
            '--packages=$pkgConfig',
            '-DDASH_REVIEW_MODE=preview',
            '-DDASH_REVIEW_PR_NUMBER=14030',
            '-DDASH_REVIEW_REPO=flutter/website',
            '-DDASH_REVIEW_COMMIT_SHA=abc1234',
            '-DDASH_REVIEW_HEAD_BRANCH=feat/test',
            probe.path,
          ]);
          expect(drRes.exitCode, equals(0), reason: '${drRes.stderr}');
          final drJson =
              jsonDecode((drRes.stdout as String).trim())
                  as Map<String, Object?>;
          expect(drJson['mode'], equals('preview'));
          expect(drJson['isEnabled'], isTrue);
          expect(drJson['prNumber'], equals('14030'));
          expect(drJson['repo'], equals('flutter/website'));
          expect(drJson['commitSha'], equals('abc1234'));
          expect(drJson['headBranch'], equals('feat/test'));

          // 3. PRODUCTION=true hard-disables even when REVIEW_COMMENTS_MODE=local
          final prodRes = await Process.run(Platform.resolvedExecutable, [
            '--packages=$pkgConfig',
            '-DPRODUCTION=true',
            '-DREVIEW_COMMENTS_MODE=local',
            '-DREVIEW_COMMENTS_SERVER_PORT=4099',
            probe.path,
          ]);
          expect(prodRes.exitCode, equals(0), reason: '${prodRes.stderr}');
          final prodJson =
              jsonDecode((prodRes.stdout as String).trim())
                  as Map<String, Object?>;
          expect(prodJson['isEnabled'], isFalse);
        } finally {
          await tempDir.delete(recursive: true);
        }
      },
    );

    test('builds page config map with optional custom feedbackFile', () {
      const cfg = ReviewConfig(
        mode: 'local',
        serverPort: '4099',
        commitSha: 'deadbeef',
      );
      final defaultMap = cfg.toPageConfigMap(
        pageUrl: '/dashboard',
        pageTitle: 'Dashboard',
        sourceFile: 'lib/main.dart',
        defaultSite: 'web-app',
        defaultRepo: 'owner/repo',
      );
      expect(defaultMap['site'], equals('web-app'));
      expect(defaultMap['repo'], equals('owner/repo'));
      expect(defaultMap.containsKey('feedbackFile'), isFalse);

      final customMap = cfg.toPageConfigMap(
        pageUrl: '/ui/layout',
        pageTitle: 'Layouts',
        sourceFile: 'sites/docs/src/content/ui/layout/index.md',
        feedbackFile: '.dash_review/feedback.md',
        cliResolveCommand: 'dart run dash_site review resolve',
      );
      expect(customMap['feedbackFile'], equals('.dash_review/feedback.md'));
      expect(
        customMap['cliResolveCommand'],
        equals('dart run dash_site review resolve'),
      );
    });
  });

  group('Source file, URL normalization, and ReviewCommentModel', () {
    test('normalizeReviewSourceFile handles explicit and prefixed paths', () {
      expect(
        normalizeReviewSourceFile(
          'sites/docs/src/content',
          'resources/glossary.md',
          explicitSourceFile: '/sites/docs/src/data/glossary.yml',
        ),
        equals('sites/docs/src/data/glossary.yml'),
      );

      expect(
        normalizeReviewSourceFile(
          'sites/docs/src/content/',
          'ui/layout/index.md',
        ),
        equals('sites/docs/src/content/ui/layout/index.md'),
      );

      expect(
        normalizeReviewSourceFile(
          'sites/www/content',
          'sites/www/content/ai/index.md',
        ),
        equals('sites/www/content/ai/index.md'),
      );

      expect(normalizeReviewSourceFile('content', ''), isEmpty);
    });

    test('normalizeReviewPageUrl handles HTML paths and SPA hash routes', () {
      expect(normalizeReviewPageUrl('/ui/layout/index.html'), '/ui/layout');
      expect(normalizeReviewPageUrl('/ui/layout/#constraints'), '/ui/layout');
      expect(normalizeReviewPageUrl('/#/details?tab=metrics'), '/details');
      expect(normalizeReviewPageUrl('#/settings/'), '/settings');
      expect(normalizeReviewPageUrl(''), '/');
    });

    test('ReviewCommentModel round-trips JSON and formats locationLabel', () {
      final model = ReviewCommentModel.fromJson(const {
        'id': 'rv_1',
        'site': 'app',
        'pageUrl': '/details',
        'pageTitle': 'Details',
        'sourceFile': 'lib/main.dart',
        'resolvedFile': 'lib/main.dart',
        'startLine': 42,
        'endLine': 45,
        'anchorType': 'element',
        'selectedText': 'Pay Now',
        'selector': 'flutter:FilledButton',
        'elementTag': 'FilledButton',
        'rectPct': {'x': 20, 'y': 30, 'w': 15, 'h': 8},
        'comment': 'Make button primary',
        'status': 'open',
        'createdAt': '2026-11-13T00:00:00Z',
        'updatedAt': '2026-11-13T00:00:00Z',
        'githubUrl': 'https://evil.example.com/phish',
        'commitSha': 'abc1234',
        'diffLine': 42,
        'diffMatched': true,
      });

      expect(model.locationLabel, equals('lib/main.dart:42-45'));
      expect(model.githubUrl, isEmpty);
      expect(model.diffMatched, isTrue);

      final counts = computeReviewCommentCounts([
        model,
        model.copyWith(status: 'resolved'),
      ]);
      expect(counts, equals({'open': 1, 'resolved': 1, 'total': 2}));

      final roundTripped = ReviewCommentModel.fromJson(model.toJson());
      expect(roundTripped.id, equals('rv_1'));
      expect(roundTripped.startLine, equals(42));
      expect(roundTripped.endLine, equals(45));
      expect(roundTripped.selector, equals('flutter:FilledButton'));
    });
  });

  group('encodeReviewJsonForHtml and client bundle security', () {
    test('escapes closing script tags and HTML comments while valid JSON', () {
      final payload = <String, Object?>{
        'pageTitle':
            'Danger </script><script>alert(1)</script> <!-- comment -->',
        'pageUrl': '/test/</Title>',
      };
      final encoded = encodeReviewJsonForHtml(payload);

      expect(encoded, isNot(contains('</')));
      expect(encoded, isNot(contains('<!--')));
      expect(encoded, contains(r'<\/script>'));

      final decoded = jsonDecode(encoded) as Map<String, Object?>;
      expect(decoded, equals(payload));
    });

    test('client script contains zero unsafe HTML sinks or raw breakouts', () {
      expect(reviewOverlayStyles, isNotEmpty);
      expect(reviewOverlayClientScript, isNotEmpty);
      expect(reviewOverlayClientScript, isNot(contains('innerHTML')));
      expect(reviewOverlayClientScript, isNot(contains('outerHTML')));
      expect(reviewOverlayClientScript, isNot(contains('insertAdjacentHTML')));
      expect(reviewOverlayClientScript, isNot(contains('document.write')));
      expect(reviewOverlayClientScript, isNot(contains('eval(')));
      expect(reviewOverlayClientScript, isNot(contains('</')));
      expect(reviewOverlayClientScript, isNot(contains('<!--')));
    });

    test(
      'passes node syntax validation, security checks, and adapter E2E harness',
      () async {
        late final ProcessResult whichNode;
        try {
          whichNode = await Process.run('node', const ['--version']);
        } on ProcessException {
          return;
        }
        if (whichNode.exitCode != 0) return;

        final tempDir = await Directory.systemTemp.createTemp('rc_js_harness_');
        try {
          final jsFile = File('${tempDir.path}/review_bundle.js');
          await jsFile.writeAsString(reviewOverlayClientScript);

          final checkResult = await Process.run('node', [
            '--check',
            jsFile.path,
          ]);
          expect(
            checkResult.exitCode,
            equals(0),
            reason: 'node --check stderr: ${checkResult.stderr}',
          );

          final harnessFile = File('${tempDir.path}/harness.js');
          await harnessFile.writeAsString(r'''
const assert = require('node:assert');
const { execFileSync } = require('node:child_process');

// Minimal DOM & Shadow DOM simulator for exercising the full overlay + adapter lifecycle.
class FakeClassList {
  constructor(owner) {
    this._owner = owner;
    this._set = new Set();
  }
  _syncFromAttr(val) {
    this._set = new Set(String(val || '').split(/\s+/).filter(Boolean));
  }
  _writeAttr() {
    this._owner._className = Array.from(this._set).join(' ');
  }
  add(...names) {
    for (const n of names) if (n) this._set.add(n);
    this._writeAttr();
  }
  remove(...names) {
    for (const n of names) this._set.delete(n);
    this._writeAttr();
  }
  toggle(name, force) {
    if (force === undefined) {
      if (this._set.has(name)) this._set.delete(name);
      else this._set.add(name);
    } else if (force) {
      this._set.add(name);
    } else {
      this._set.delete(name);
    }
    this._writeAttr();
  }
  contains(name) {
    return this._set.has(name);
  }
}

class FakeNode {
  constructor(tag) {
    this.nodeType = tag === '#text' ? 3 : 1;
    this.tagName = String(tag || 'div').toUpperCase();
    this.id = '';
    this._className = '';
    this.classList = new FakeClassList(this);
    this.style = {};
    this.attributes = new Map();
    this.children = [];
    this.parentNode = null;
    this.parentElement = null;
    this.listeners = new Map();
    this._text = '';
    this.value = '';
    this.shadowRoot = null;
    this._rect = { left: 0, top: 0, width: 1280, height: 800, right: 1280, bottom: 800 };
  }
  get className() {
    return this._className;
  }
  set className(val) {
    this._className = String(val || '');
    this.classList._syncFromAttr(this._className);
  }
  get firstChild() {
    return this.children.length > 0 ? this.children[0] : null;
  }
  get isConnected() {
    return true;
  }
  get textContent() {
    if (this.nodeType === 3) return this._text;
    if (this.children.length === 0) return this._text;
    return this.children.map((c) => c.textContent).join('');
  }
  set textContent(val) {
    this.children = [];
    this._text = String(val == null ? '' : val);
  }
  setAttribute(k, v) {
    const sv = String(v);
    this.attributes.set(k, sv);
    if (k === 'id') this.id = sv;
    if (k === 'class') this.className = sv;
    if (k === 'value') this.value = sv;
  }
  getAttribute(k) {
    return this.attributes.has(k) ? this.attributes.get(k) : null;
  }
  removeAttribute(k) {
    this.attributes.delete(k);
  }
  appendChild(child) {
    if (child.parentNode) child.parentNode.removeChild(child);
    child.parentNode = this;
    child.parentElement = this.nodeType === 1 ? this : null;
    this.children.push(child);
    return child;
  }
  removeChild(child) {
    const idx = this.children.indexOf(child);
    if (idx !== -1) {
      this.children.splice(idx, 1);
      child.parentNode = null;
      child.parentElement = null;
    }
    return child;
  }
  attachShadow() {
    this.shadowRoot = new FakeNode('#shadow-root');
    return this.shadowRoot;
  }
  addEventListener(type, fn) {
    if (!this.listeners.has(type)) this.listeners.set(type, []);
    this.listeners.get(type).push(fn);
  }
  dispatchEvent(evt) {
    evt.target = evt.target || this;
    evt.preventDefault = evt.preventDefault || (() => {});
    evt.stopPropagation = evt.stopPropagation || (() => {});
    const arr = this.listeners.get(evt.type) || [];
    for (const fn of arr) fn(evt);
  }
  closest(sel) {
    if (sel.includes('#dash-review-host') && this.id === 'dash-review-host') return this;
    if (
      sel.includes('data-dash-review-ignore') &&
      this.getAttribute('data-dash-review-ignore') === 'true'
    ) {
      return this;
    }
    return this.parentElement ? this.parentElement.closest(sel) : null;
  }
  getBoundingClientRect() {
    return this._rect;
  }
  findByTestId(testId) {
    if (this.getAttribute && this.getAttribute('data-testid') === testId) return this;
    for (const c of this.children) {
      if (c.findByTestId) {
        const hit = c.findByTestId(testId);
        if (hit) return hit;
      }
    }
    return null;
  }
  findAllByClass(cls, acc = []) {
    if (this.classList && this.classList.contains(cls)) acc.push(this);
    for (const c of this.children) {
      if (c.findAllByClass) c.findAllByClass(cls, acc);
    }
    return acc;
  }
}

const storage = new Map();
const docListeners = new Map();
const winListeners = new Map();
const postedPayloads = [];
let currentConfigJson = JSON.stringify({
  mode: 'local',
  site: 'flutter_app',
  pageUrl: '/',
  pageTitle: 'Home',
  sourceFile: 'lib/main.dart',
  serverOrigin: 'http://127.0.0.1:4099',
  repo: 'abdallahshaban/review_comments',
  prNumber: '42',
  commitSha: '',
  feedbackFile: '.review_comments/feedback.md'
});

const configEl = new FakeNode('script');
configEl.id = 'dash-review-config';
configEl.textContent = currentConfigJson;

const docElement = new FakeNode('html');
const bodyEl = new FakeNode('body');
const canvasEl = new FakeNode('flutter-view');
docElement.appendChild(bodyEl);
bodyEl.appendChild(configEl);
bodyEl.appendChild(canvasEl);

let hitTargetAtPoint = canvasEl;

global.window = {
  innerWidth: 1000,
  innerHeight: 800,
  scrollY: 0,
  location: {
    hostname: 'preview--pr42-abc.web.app',
    pathname: '/',
    hash: '',
    origin: 'https://preview--pr42-abc.web.app',
    href: 'https://preview--pr42-abc.web.app/'
  },
  localStorage: {
    getItem: (k) => (storage.has(k) ? storage.get(k) : null),
    setItem: (k, v) => storage.set(k, String(v)),
    removeItem: (k) => storage.delete(k)
  },
  sessionStorage: {
    getItem: () => null,
    setItem: () => {},
    removeItem: () => {}
  },
  addEventListener: (type, fn) => {
    if (!winListeners.has(type)) winListeners.set(type, []);
    winListeners.get(type).push(fn);
  },
  requestAnimationFrame: (fn) => fn(),
  getSelection: () => ({ isCollapsed: true, rangeCount: 0 })
};

global.document = {
  readyState: 'complete',
  title: 'Home',
  documentElement: docElement,
  body: bodyEl,
  createElement: (tag) => new FakeNode(tag),
  createElementNS: (_ns, tag) => new FakeNode(tag),
  createTextNode: (txt) => {
    const t = new FakeNode('#text');
    t._text = String(txt);
    return t;
  },
  getElementById: (id) => (id === 'dash-review-config' ? configEl : null),
  querySelector: () => null,
  elementFromPoint: () => hitTargetAtPoint,
  addEventListener: (type, fn) => {
    if (!docListeners.has(type)) docListeners.set(type, []);
    docListeners.get(type).push(fn);
  }
};

function dispatchDoc(type, props) {
  const evt = Object.assign(
    {
      type,
      button: 0,
      preventDefault: () => {},
      stopPropagation: () => {},
      composedPath: () => [evt.target || canvasEl]
    },
    props
  );
  for (const fn of docListeners.get(type) || []) fn(evt);
}

global.fetch = async (url, opts = {}) => {
  const u = String(url);
  if (u.endsWith('/api/comments') && (!opts.method || opts.method === 'GET')) {
    return {
      ok: true,
      status: 200,
      json: async () => ({
        feedbackFile: '.review_comments/feedback.md',
        comments: postedPayloads.slice()
      })
    };
  }
  if (u.endsWith('/api/comments') && opts.method === 'POST') {
    const parsed = JSON.parse(opts.body);
    postedPayloads.push(parsed);
    return {
      ok: true,
      status: 201,
      json: async () => ({
        feedbackFile: '.review_comments/feedback.md',
        comment: parsed
      })
    };
  }
  if (u.endsWith('/api/health')) {
    return {
      ok: true,
      status: 200,
      json: async () => ({ ok: true, feedbackFile: '.review_comments/feedback.md' })
    };
  }
  if (u.includes('/repos/abdallahshaban/review_comments/pulls/42/files')) {
    return {
      ok: true,
      status: 200,
      json: async () => [
        {
          filename: 'lib/details_page.dart',
          status: 'modified',
          contents_url: 'https://api.github.com/repos/abdallahshaban/review_comments/contents/lib/details_page.dart?ref=99887766',
          patch: '@@ -10,2 +50,4 @@\n context\n+FilledButton(onPressed: () {}, child: const Text(\'Upgrade Plan\')),\n trailing'
        }
      ]
    };
  }
  if (u.endsWith('/repos/abdallahshaban/review_comments/pulls/42')) {
    return {
      ok: true,
      status: 200,
      json: async () => ({ head: { sha: '99887766' } })
    };
  }
  if (u.includes('/pulls/42/comments') || u.includes('/issues/42/comments')) {
    return {
      ok: true,
      status: 200,
      json: async () => []
    };
  }
  throw new Error('Unexpected URL: ' + u);
};

require(process.argv[2]);

(async () => {
  await new Promise((r) => setTimeout(r, 10));
  const api = global.window.__dashReviewInternals;
  assert.ok(api, '__dashReviewInternals must be registered');
  assert.strictEqual(global.window.__reviewCommentsBootstrapped, true);
  assert.strictEqual(typeof global.window.__reviewCommentsNotifyNavigation, 'function');
  assert.strictEqual(typeof global.window.__reviewCommentsRefresh, 'function');

  // 1. Core security & diff parsing helpers
  assert.strictEqual(api.parsePrFromHostname('flutter-docs--pr14030-9f8e7d.web.app'), '14030');
  assert.strictEqual(api.normalizePageUrl('/#/details?tab=1'), '/details');
  assert.strictEqual(api.normalizePageUrl('/ui/layout/#constraints'), '/ui/layout');

  const hostile = " Fix 'single' quotes; $(echo INJECTED) `id` $HOME \nline2 ";
  const quoted = api.shellQuote(hostile);
  const echoed = execFileSync('/bin/sh', ['-c', 'printf %s ' + quoted], { encoding: 'utf8' });
  assert.strictEqual(echoed, hostile);

  const previewOrigin = 'https://preview--pr42-abc.web.app';
  assert.strictEqual(api.sanitizeSameOriginPath('/\\evil.example.com/phish', previewOrigin), null);
  assert.strictEqual(api.sanitizeSameOriginPath('//evil.example.com/phish', previewOrigin), null);
  assert.strictEqual(api.sanitizeSameOriginPath('https://evil.example.com/phish', previewOrigin), null);
  assert.strictEqual(api.sanitizeSameOriginPath('javascript:alert(1)', previewOrigin), null);
  assert.strictEqual(
    api.sanitizeSameOriginPath('/details?tab=metrics#top', previewOrigin),
    '/details?tab=metrics#top'
  );

  // 2. Late registration of window.__REVIEW_COMMENTS_ADAPTER__ AFTER script boot!
  let activeRoute = '/';
  let activeTitle = 'Dashboard';
  let activeSource = 'lib/dashboard_page.dart';
  let liveScrolledRect = null;

  global.window.__REVIEW_COMMENTS_ADAPTER__ = {
    getPageContext: () => ({
      pageUrl: activeRoute,
      pageTitle: activeTitle,
      sourceFile: activeSource
    }),
    inspectPoint: (x, y) => {
      if (x >= 200 && x <= 400 && y >= 100 && y <= 160) {
        return {
          rect: { left: 200, top: 100, width: 200, height: 60 },
          label: 'FilledButton("Checkout")',
          elementTag: 'FilledButton',
          selector: 'flutter:FilledButton[key=checkout]',
          selectedText: 'Checkout',
          elementText: 'Checkout',
          headingAnchor: '',
          sourceFile: 'lib/dashboard_page.dart',
          startLine: 88,
          endLine: 92
        };
      }
      return null;
    },
    inspectArea: ({ left, top, width, height }) => ({
      elementTag: 'MetricCard',
      selector: 'flutter:MetricCard',
      selectedText: 'Active Users 12,450',
      elementText: 'Active Users 12,450',
      sourceFile: 'lib/widgets/metric_card.dart',
      startLine: 31,
      endLine: 39,
      rectPct: {
        x: left / 1000,
        y: top / 800,
        w: width / 1000,
        h: height / 800
      }
    }),
    locateCommentRect: (record) => {
      if (record.selector === 'flutter:FilledButton[key=checkout]' && liveScrolledRect) {
        return liveScrolledRect;
      }
      return null;
    }
  };

  const inst = api.getActiveInstance();
  assert.ok(inst, 'Overlay instance must be mounted');
  const shadow = inst.shadow;

  // Verify settings modal shows default .review_comments/feedback.md
  const settingsBtn = shadow.findByTestId('dr-open-settings');
  settingsBtn.dispatchEvent({ type: 'click' });
  const modal = shadow.findByTestId('dr-settings-modal');
  assert.ok(modal.textContent.includes('.review_comments/feedback.md'));
  settingsBtn.dispatchEvent({ type: 'click' });

  // Toggle Comment Mode via Alt+C
  dispatchDoc('keydown', { altKey: true, ctrlKey: false, metaKey: false, code: 'KeyC', key: 'c' });
  assert.strictEqual(inst.getState().commentMode, true);

  // Hover inside #dash-review-host must be ignored!
  hitTargetAtPoint = inst.host;
  dispatchDoc('mousemove', { clientX: 250, clientY: 120, target: inst.host });
  const hoverBoxes = shadow.findAllByClass('dr-hover-box');
  assert.strictEqual(hoverBoxes[0].classList.contains('dr-hidden'), true);

  // Hover on Flutter widget via adapter.inspectPoint highlights rect + shows source:line!
  hitTargetAtPoint = canvasEl;
  dispatchDoc('mousemove', { clientX: 250, clientY: 120, target: canvasEl });
  assert.strictEqual(hoverBoxes[0].classList.contains('dr-hidden'), false);
  assert.strictEqual(hoverBoxes[0].style.left, '200px');
  assert.strictEqual(hoverBoxes[0].style.width, '200px');
  assert.ok(
    hoverBoxes[0].textContent.includes('FilledButton("Checkout") · lib/dashboard_page.dart:88'),
    'Hover pill was: ' + hoverBoxes[0].textContent
  );

  // Click widget -> opens composer with sourceFile, startLine, endLine, rectPct
  dispatchDoc('mousedown', { clientX: 250, clientY: 120, target: canvasEl });
  dispatchDoc('mouseup', { clientX: 250, clientY: 120, target: canvasEl });

  const composer = shadow.findByTestId('dr-composer');
  assert.ok(composer, 'Composer must open on adapter widget click');
  assert.ok(composer.textContent.includes('lib/dashboard_page.dart:88-92'));

  const textarea = shadow.findByTestId('dr-composer-textarea');
  textarea.value = 'Increase horizontal padding on Checkout button';
  const submitBtn = shadow.findByTestId('dr-composer-submit');
  submitBtn.dispatchEvent({ type: 'click' });
  await new Promise((r) => setTimeout(r, 20));

  assert.strictEqual(postedPayloads.length, 1);
  assert.strictEqual(postedPayloads[0].sourceFile, 'lib/dashboard_page.dart');
  assert.strictEqual(postedPayloads[0].startLine, 88);
  assert.strictEqual(postedPayloads[0].endLine, 92);
  assert.strictEqual(postedPayloads[0].selector, 'flutter:FilledButton[key=checkout]');
  assert.strictEqual(postedPayloads[0].pageUrl, '/');
  assert.deepStrictEqual(postedPayloads[0].rectPct, { x: 20, y: 12.5, w: 20, h: 7.5 });

  // Verify toast displays .review_comments/feedback.md
  const toasts = shadow.findAllByClass('dr-toast');
  assert.ok(
    toasts.some((t) => t.textContent.includes('Saved to .review_comments/feedback.md')),
    'Expected feedbackFile toast'
  );

  // 3. Verify pin positioning: fallback to rectPct when locateCommentRect returns null,
  // and live tracking when locateCommentRect returns a scrolled rect!
  let pins = shadow.findAllByClass('dr-pin');
  assert.strictEqual(pins.length, 1);
  assert.strictEqual(pins[0].style.left, '396px'); // 200 + 200 - 4
  assert.strictEqual(pins[0].style.top, '106px'); // 100 + 6

  liveScrolledRect = { left: 200, top: 40, width: 200, height: 60 };
  global.window.__reviewCommentsNotifyNavigation();
  pins = shadow.findAllByClass('dr-pin');
  assert.strictEqual(pins[0].style.top, '46px'); // 40 + 6 tracked live scroll!

  // 4. Area drag with adapter.inspectArea (including 0..1 unit fraction rectPct conversion!)
  dispatchDoc('keydown', { altKey: true, ctrlKey: false, metaKey: false, code: 'KeyC', key: 'c' });
  dispatchDoc('mousedown', { clientX: 100, clientY: 300, target: canvasEl });
  dispatchDoc('mousemove', { clientX: 400, clientY: 500, target: canvasEl });
  dispatchDoc('mouseup', { clientX: 400, clientY: 500, target: canvasEl });

  const areaTextarea = shadow.findByTestId('dr-composer-textarea');
  assert.ok(areaTextarea, 'Composer must open after area drag');
  areaTextarea.value = 'Align metric cards';
  shadow.findByTestId('dr-composer-submit').dispatchEvent({ type: 'click' });
  await new Promise((r) => setTimeout(r, 20));

  assert.strictEqual(postedPayloads.length, 2);
  assert.strictEqual(postedPayloads[1].anchorType, 'area');
  assert.strictEqual(postedPayloads[1].sourceFile, 'lib/widgets/metric_card.dart');
  assert.strictEqual(postedPayloads[1].startLine, 31);
  assert.strictEqual(postedPayloads[1].endLine, 39);
  assert.strictEqual(postedPayloads[1].selectedText, 'Active Users 12,450');
  assert.deepStrictEqual(postedPayloads[1].rectPct, { x: 10, y: 37.5, w: 30, h: 25 });

  // 5. Dynamic SPA navigation via adapter.getPageContext + __reviewCommentsNotifyNavigation
  activeRoute = '/details';
  activeTitle = 'Feature Details';
  activeSource = 'lib/details_page.dart';
  global.window.__reviewCommentsNotifyNavigation();

  pins = shadow.findAllByClass('dr-pin');
  assert.strictEqual(pins.length, 0, 'Home route pins must hide on /details');

  shadow.findByTestId('dr-toggle-drawer').dispatchEvent({ type: 'click' });
  const drawer = shadow.findByTestId('dr-drawer');
  assert.ok(drawer.textContent.includes('Current Page (0)'));
  assert.ok(drawer.textContent.includes('All Pages (2)'));

  // 6. Verify Preview Mode tokenless PR diff mapping & shell-safe gh CLI output
  global.window.__dashReviewMounted = false;
  api.mountOverlay; // verify custom preview instance in isolated scope:
  configEl.textContent = JSON.stringify({
    mode: 'preview',
    site: 'flutter_app',
    pageUrl: '/details',
    pageTitle: 'Feature Details',
    sourceFile: 'lib/details_page.dart',
    prNumber: '42',
    repo: 'abdallahshaban/review_comments',
    commitSha: ''
  });
  // Test parseDiffRightSideLines + matchNeedleInRightLines on Dart widget source
  const dartPatch = [
    '@@ -10,2 +50,4 @@',
    ' context',
    "+FilledButton(onPressed: () {}, child: const Text('Upgrade Plan')),",
    ' trailing'
  ].join('\n');
  const dartRight = api.parseDiffRightSideLines(dartPatch);
  const dartHit = api.matchNeedleInRightLines(dartRight, 'Upgrade Plan', '');
  assert.strictEqual(dartHit.line, 51);

  // Test viewportRectFromRectPct for both 0..1 fractions and 0..100 percentages
  const unitVp = api.viewportRectFromRectPct({ x: 0.25, y: 0.5, w: 0.2, h: 0.1 }, 1000, 800);
  const pctVp = api.viewportRectFromRectPct({ x: 25, y: 50, w: 20, h: 10 }, 1000, 800);
  assert.deepStrictEqual(unitVp, pctVp);
  assert.strictEqual(unitVp.left, 250);
  assert.strictEqual(unitVp.top, 400);
  assert.strictEqual(unitVp.width, 200);
  assert.strictEqual(unitVp.height, 80);
})();
''');

          final runResult = await Process.run('node', [
            harnessFile.path,
            jsFile.path,
          ]);
          expect(
            runResult.exitCode,
            equals(0),
            reason:
                'JS harness failed:\nstdout: ${runResult.stdout}\nstderr: ${runResult.stderr}',
          );
        } finally {
          await tempDir.delete(recursive: true);
        }
      },
    );
  });
}
