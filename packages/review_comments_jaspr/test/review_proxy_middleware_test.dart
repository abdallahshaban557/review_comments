// Copyright (c) 2026, Abdallah Shaban. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:jaspr/server.dart';
import 'package:review_comments/review_comments.dart';
import 'package:review_comments_jaspr/server.dart';
import 'package:test/test.dart';

void main() {
  group('reviewLocalProxyMiddleware', () {
    test(
      'proxies same-origin /__dash_review/api/* requests to loopback server',
      () async {
        final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => upstream.close(force: true));

        upstream.listen((req) async {
          final body = await utf8.decoder.bind(req).join();
          req.response
            ..statusCode = req.method == 'POST'
                ? HttpStatus.created
                : HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode({
                'ok': true,
                'method': req.method,
                'path': req.uri.path,
                'query': req.uri.query,
                'echo': body.isEmpty ? null : jsonDecode(body),
              }),
            );
          await req.response.close();
        });

        final middleware = reviewLocalProxyMiddleware(
          config: ReviewConfig(
            mode: 'local',
            serverPort: '${upstream.port}',
            site: 'www',
          ),
        );
        final handler = middleware(
          (_) => Response.ok(
            'site html',
            headers: const {'content-type': 'text/html'},
          ),
        );

        // Non-proxy routes pass straight through.
        final pageRes = await handler(
          Request('GET', Uri.parse('http://localhost:8082/ui/layout')),
        );
        expect(pageRes.statusCode, HttpStatus.ok);
        expect(await pageRes.readAsString(), 'site html');

        // Health GET over same-origin Cloudtop / VS Code tunnel hostname works.
        final healthRes = await handler(
          Request(
            'GET',
            Uri.parse(
              'https://8082-dev.proxy.googlers.com/__dash_review/api/health',
            ),
          ),
        );
        expect(healthRes.statusCode, HttpStatus.ok);
        final healthJson =
            jsonDecode(await healthRes.readAsString()) as Map<String, Object?>;
        expect(healthJson['ok'], isTrue);
        expect(healthJson['path'], '/api/health');

        // Same-origin POST forwards JSON payload cleanly.
        final postRes = await handler(
          Request(
            'POST',
            Uri.parse(
              'https://8082-dev.proxy.googlers.com/__dash_review/api/comments?site=www',
            ),
            headers: const {
              'content-type': 'application/json',
              'origin': 'https://8082-dev.proxy.googlers.com',
              'sec-fetch-site': 'same-origin',
            },
            body: jsonEncode({'comment': 'Great hero layout'}),
          ),
        );
        expect(postRes.statusCode, HttpStatus.created);
        final postJson =
            jsonDecode(await postRes.readAsString()) as Map<String, Object?>;
        expect(postJson['ok'], isTrue);
        expect(postJson['path'], '/api/comments');
        expect(postJson['query'], 'site=www');
        expect(
          (postJson['echo'] as Map<String, Object?>)['comment'],
          'Great hero layout',
        );
      },
    );

    test(
      'rejects cross-site requests and mismatched Origin headers with 403',
      () async {
        final middleware = reviewLocalProxyMiddleware(
          config: const ReviewConfig(mode: 'local', serverPort: '4099'),
        );
        final handler = middleware((_) => Response.ok('unused'));

        final crossSiteRes = await handler(
          Request(
            'GET',
            Uri.parse('http://localhost:8082/__dash_review/api/comments'),
            headers: const {'sec-fetch-site': 'cross-site'},
          ),
        );
        expect(crossSiteRes.statusCode, HttpStatus.forbidden);

        final badOriginRes = await handler(
          Request(
            'POST',
            Uri.parse('http://localhost:8082/__dash_review/api/comments'),
            headers: const {'origin': 'https://evil.example.com'},
            body: '{"comment":"csrf"}',
          ),
        );
        expect(badOriginRes.statusCode, HttpStatus.forbidden);
      },
    );
  });
}
