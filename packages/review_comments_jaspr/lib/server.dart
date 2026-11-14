// Copyright (c) 2026, Abdallah Shaban. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Server-side Jaspr middleware that proxies `/__dash_review/api/*` requests on
/// the main site port directly to the loopback `ReviewLocalServer` instance.
///
/// This enables local review comment syncing to work seamlessly over
/// same-origin HTTP/HTTPS without needing separate port forwarding on VS Code
/// Remote, Cloudtop web previews, SSH tunnels, or Private Network Access CORS.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:jaspr/server.dart';
import 'package:review_comments/review_comments.dart';

/// URL prefix mounted on the Jaspr `ServerApp` for same-origin local review API
/// calls.
const String reviewProxyPathPrefix = '/__dash_review';

const int _maxProxyRequestBodyBytes = 1024 * 1024;

/// Registers the same-origin `/__dash_review/api/*` proxy middleware on Jaspr's
/// [ServerApp] when local visual review mode is enabled.
///
/// Safe to call unconditionally in `main.server.dart` before `runApp(...)`:
/// returns immediately as a no-op in production builds, static non-review CI
/// builds, and preview builds.
void registerReviewLocalProxyMiddleware({ReviewConfig? config}) {
  final effectiveConfig = config ?? ReviewConfig.environment;
  if (!effectiveConfig.isEnabled || effectiveConfig.mode != 'local') {
    return;
  }
  ServerApp.addMiddleware(reviewLocalProxyMiddleware(config: effectiveConfig));
}

/// Creates a `shelf`-compatible middleware (`Handler Function(Handler)`) that
/// forwards same-origin `/__dash_review/api/*` requests to
/// [ReviewConfig.serverOrigin].
Handler Function(Handler) reviewLocalProxyMiddleware({ReviewConfig? config}) {
  final effectiveConfig = config ?? ReviewConfig.environment;

  return (Handler innerHandler) {
    return (Request request) async {
      final reqPath = request.requestedUri.path;
      if (!reqPath.startsWith('$reviewProxyPathPrefix/api/')) {
        return innerHandler(request);
      }

      if (!effectiveConfig.isEnabled ||
          effectiveConfig.mode != 'local' ||
          effectiveConfig.serverOrigin.isEmpty) {
        return _jsonResponse(HttpStatus.notFound, {
          'ok': false,
          'error': 'Local review proxy is not active.',
        });
      }

      // Block cross-site CSRF / data exfiltration attempts while allowing
      // legitimate same-origin requests from localhost, VS Code tunnels, or
      // Cloudtop web preview hostnames.
      final secFetchSite = request.headers['sec-fetch-site']?.trim();
      if (secFetchSite == 'cross-site') {
        return _jsonResponse(HttpStatus.forbidden, {
          'ok': false,
          'error': 'Cross-site requests to local review proxy are forbidden.',
        });
      }

      final originHeader = request.headers['origin']?.trim();
      if (originHeader != null && originHeader.isNotEmpty) {
        final originUri = Uri.tryParse(originHeader);
        if (originUri == null ||
            originUri.host.toLowerCase() !=
                request.requestedUri.host.toLowerCase()) {
          return _jsonResponse(HttpStatus.forbidden, {
            'ok': false,
            'error': 'Origin mismatch on local review proxy.',
          });
        }
      }

      if (request.method == 'OPTIONS') {
        return Response(
          HttpStatus.noContent,
          headers: const {'cache-control': 'no-store'},
        );
      }

      final upstreamSubpath = reqPath.substring(reviewProxyPathPrefix.length);
      final querySuffix = request.requestedUri.hasQuery
          ? '?${request.requestedUri.query}'
          : '';
      final targetUri = Uri.parse(
        '${effectiveConfig.serverOrigin}$upstreamSubpath$querySuffix',
      );

      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 3);
      try {
        final bodyBuilder = BytesBuilder(copy: false);
        await for (final chunk in request.read()) {
          if (bodyBuilder.length + chunk.length > _maxProxyRequestBodyBytes) {
            return _jsonResponse(HttpStatus.badRequest, {
              'ok': false,
              'error': 'Request body exceeds maximum size.',
            });
          }
          bodyBuilder.add(chunk);
        }
        final bodyBytes = bodyBuilder.takeBytes();

        final upstreamReq = await client.openUrl(request.method, targetUri);
        upstreamReq.headers.set(HttpHeaders.acceptHeader, 'application/json');
        if (request.headers['content-type'] case final String contentType
            when contentType.isNotEmpty) {
          upstreamReq.headers.set(HttpHeaders.contentTypeHeader, contentType);
        }
        if (bodyBytes.isNotEmpty) {
          upstreamReq.contentLength = bodyBytes.length;
          upstreamReq.add(bodyBytes);
        }

        final upstreamRes = await upstreamReq.close().timeout(
          const Duration(seconds: 5),
        );
        final resBuilder = BytesBuilder(copy: false);
        await for (final chunk in upstreamRes) {
          resBuilder.add(chunk);
        }

        return Response(
          upstreamRes.statusCode,
          body: resBuilder.takeBytes(),
          headers: const {
            'content-type': 'application/json; charset=utf-8',
            'cache-control': 'no-store',
          },
        );
      } on Object catch (error) {
        return _jsonResponse(HttpStatus.badGateway, {
          'ok': false,
          'error':
              'Local review sync server unreachable at '
              '${effectiveConfig.serverOrigin}: $error',
        });
      } finally {
        client.close(force: true);
      }
    };
  };
}

Response _jsonResponse(int statusCode, Map<String, Object?> payload) =>
    Response(
      statusCode,
      body: jsonEncode(payload),
      headers: const {
        'content-type': 'application/json; charset=utf-8',
        'cache-control': 'no-store',
      },
    );
