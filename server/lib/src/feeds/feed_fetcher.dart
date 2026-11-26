import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../http/json.dart';

class FetchResult {
  const FetchResult({
    required this.notModified,
    this.body,
    this.etag,
    this.lastModified,
    this.finalUrl,
  });

  final bool notModified;
  final String? body;
  final String? etag;
  final String? lastModified;
  final Uri? finalUrl;
}

/// Downloads feeds with conditional requests (ETag / If-Modified-Since).
class FeedFetcher {
  FeedFetcher({http.Client? client, required this.userAgent})
      : _client = client ?? http.Client();

  final http.Client _client;
  final String userAgent;

  static const maxBytes = 25 * 1024 * 1024;
  static const timeout = Duration(seconds: 30);

  Future<FetchResult> fetch(
    String url, {
    String? etag,
    String? lastModified,
  }) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
      throw ApiException.badRequest('Invalid feed URL');
    }
    final req = http.Request('GET', uri)
      ..followRedirects = true
      ..maxRedirects = 5
      ..headers.addAll({
        'user-agent': userAgent,
        'accept': 'application/rss+xml, application/xml, text/xml, */*',
        'if-none-match': ?etag,
        'if-modified-since': ?lastModified,
      });

    final res = await _client.send(req).timeout(timeout);
    if (res.statusCode == 304) {
      await res.stream.drain<void>();
      return FetchResult(notModified: true, etag: etag, lastModified: lastModified);
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      await res.stream.drain<void>();
      throw FeedFetchException('HTTP ${res.statusCode}', res.statusCode);
    }

    final bytes = <int>[];
    await for (final chunk in res.stream.timeout(timeout)) {
      bytes.addAll(chunk);
      if (bytes.length > maxBytes) throw FeedFetchException('Feed too large');
    }
    return FetchResult(
      notModified: false,
      body: _decode(bytes, res.headers['content-type']),
      etag: res.headers['etag'],
      lastModified: res.headers['last-modified'],
      finalUrl: req.url,
    );
  }

  static String _decode(List<int> bytes, String? contentType) {
    final head = latin1.decode(bytes.take(200).toList(), allowInvalid: true);
    final declared = RegExp(r'''encoding=["']([\w-]+)["']''')
            .firstMatch(head)?[1] ??
        RegExp(r'charset=([\w-]+)').firstMatch(contentType ?? '')?[1];
    if (declared != null &&
        const {'iso-8859-1', 'latin1', 'windows-1252'}
            .contains(declared.toLowerCase())) {
      return latin1.decode(bytes, allowInvalid: true);
    }
    var s = utf8.decode(bytes, allowMalformed: true);
    if (s.startsWith('﻿')) s = s.substring(1);
    return s;
  }

  void close() => _client.close();
}

class FeedFetchException implements Exception {
  FeedFetchException(this.message, [this.statusCode]);
  final String message;
  final int? statusCode;
  @override
  String toString() => 'FeedFetchException: $message';
}
