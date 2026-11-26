import 'dart:convert';

import 'package:bettercast_core/bettercast_core.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

final _log = Logger('search');

/// Podcast directory search: Podcast Index (when configured) + iTunes.
/// API keys never leave the server.
class SearchService {
  SearchService({
    http.Client? client,
    this.podcastIndexKey,
    this.podcastIndexSecret,
    required this.userAgent,
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final String? podcastIndexKey;
  final String? podcastIndexSecret;
  final String userAgent;

  final _cache = <String, (DateTime, List<SearchResult>)>{};
  static const _cacheTtl = Duration(minutes: 10);

  bool get _piEnabled => podcastIndexKey != null && podcastIndexSecret != null;

  Future<List<SearchResult>> search(String term, {int limit = 30}) async {
    final q = term.trim();
    if (q.isEmpty) return [];
    final key = 'search:${q.toLowerCase()}';
    final cached = _cache[key];
    if (cached != null && DateTime.now().difference(cached.$1) < _cacheTtl) {
      return cached.$2;
    }

    final futures = [
      if (_piEnabled) _guard(_podcastIndexSearch(q, limit)),
      _guard(_itunesSearch(q, limit)),
    ];
    final lists = await Future.wait(futures);
    final merged = <String, SearchResult>{};
    for (final list in lists) {
      for (final r in list) {
        merged.putIfAbsent(r.podcastId, () => r);
      }
    }
    final out = merged.values.take(limit).toList();
    _cache[key] = (DateTime.now(), out);
    if (_cache.length > 500) _cache.remove(_cache.keys.first);
    return out;
  }

  /// Top podcasts for a country, optionally limited to an Apple genre id
  /// (e.g. 1309 = TV & Film). Apple's charts first (best for non-English
  /// markets), Podcast Index trending as a fallback.
  Future<List<SearchResult>> trending({
    String country = 'fr',
    String? genre,
    int limit = 40,
  }) async {
    final cc = RegExp(r'^[a-z]{2}$').hasMatch(country) ? country : 'fr';
    final g = genre != null && RegExp(r'^\d{1,5}$').hasMatch(genre) ? genre : null;
    final key = 'trending:$cc:$g';
    final cached = _cache[key];
    if (cached != null && DateTime.now().difference(cached.$1) < _cacheTtl * 6) {
      return cached.$2;
    }
    var res = await _guard(_appleCharts(cc, g, limit));
    if (res.isEmpty && _piEnabled && g == null) {
      res = await _guard(_pi('/podcasts/trending', {'max': '$limit', 'lang': cc})
          .then((j) => _piFeeds(j['feeds'])));
    }
    if (res.isNotEmpty) _cache[key] = (DateTime.now(), res);
    return res;
  }

  Future<List<SearchResult>> _appleCharts(String cc, String? genre, int limit) async {
    final path = '/$cc/rss/toppodcasts/limit=$limit${genre == null ? '' : '/genre=$genre'}/json';
    final chart = await _client
        .get(Uri.https('itunes.apple.com', path), headers: {'User-Agent': userAgent})
        .timeout(const Duration(seconds: 10));
    if (chart.statusCode != 200) throw Exception('Apple charts HTTP ${chart.statusCode}');
    final feed = (jsonDecode(utf8.decode(chart.bodyBytes)) as Map)['feed'] as Map?;
    final entries = feed?['entry'];
    final ids = <String>[
      for (final e in (entries is List ? entries : [?entries]).whereType<Map>())
        if ((e['id'] as Map?)?['attributes']?['im:id'] case final String id) id,
    ];
    if (ids.isEmpty) return [];
    // The chart has no feed URLs: resolve them with one lookup call.
    final res = await _client.get(
      Uri.https('itunes.apple.com', '/lookup',
          {'id': ids.join(','), 'entity': 'podcast', 'country': cc}),
      headers: {'User-Agent': userAgent},
    ).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) throw Exception('iTunes lookup HTTP ${res.statusCode}');
    final byId = {
      for (final r in ((jsonDecode(utf8.decode(res.bodyBytes)) as Map)['results'] as List? ?? [])
          .whereType<Map>())
        '${r['collectionId']}': r,
    };
    return [
      for (final id in ids)
        if (byId[id] case final Map r when r['feedUrl'] is String) _itunesResult(r),
    ];
  }

  Future<List<SearchResult>> _guard(Future<List<SearchResult>> f) =>
      f.catchError((Object e) {
        _log.warning('Search provider failed: $e');
        return <SearchResult>[];
      });

  Future<List<SearchResult>> _podcastIndexSearch(String q, int limit) async {
    final j = await _pi('/search/byterm', {'q': q, 'max': '$limit'});
    return _piFeeds(j['feeds']);
  }

  List<SearchResult> _piFeeds(Object? feeds) => [
        if (feeds is List)
          for (final f in feeds.whereType<Map>())
            if (f['url'] is String && (f['url'] as String).isNotEmpty)
              SearchResult(
                feedUrl: f['url'] as String,
                title: '${f['title'] ?? ''}',
                author: f['author'] as String?,
                imageUrl: _nonEmpty(f['artwork']) ?? _nonEmpty(f['image']),
                description: f['description'] as String?,
                episodeCount: (f['episodeCount'] as num?)?.toInt(),
                hasVideo: f['medium'] == 'video',
              ),
      ];

  Future<Map<String, dynamic>> _pi(String path, Map<String, String> q) async {
    final now = '${DateTime.now().millisecondsSinceEpoch ~/ 1000}';
    final auth = sha1
        .convert(utf8.encode('$podcastIndexKey$podcastIndexSecret$now'))
        .toString();
    final res = await _client.get(
      Uri.https('api.podcastindex.org', '/api/1.0$path', q),
      headers: {
        'User-Agent': userAgent,
        'X-Auth-Key': podcastIndexKey!,
        'X-Auth-Date': now,
        'Authorization': auth,
      },
    ).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) {
      throw Exception('Podcast Index HTTP ${res.statusCode}');
    }
    return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  }

  Future<List<SearchResult>> _itunesSearch(String q, int limit) async {
    final res = await _client.get(
      Uri.https('itunes.apple.com', '/search', {
        'media': 'podcast',
        'term': q,
        'limit': '$limit',
      }),
      headers: {'User-Agent': userAgent},
    ).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) throw Exception('iTunes HTTP ${res.statusCode}');
    final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return [
      for (final r in (j['results'] as List? ?? []).whereType<Map>())
        if (r['feedUrl'] is String)
          _itunesResult(r),
    ];
  }

  static SearchResult _itunesResult(Map r) => SearchResult(
        feedUrl: r['feedUrl'] as String,
        title: '${r['collectionName'] ?? r['trackName'] ?? ''}',
        author: r['artistName'] as String?,
        imageUrl: r['artworkUrl600'] as String? ?? r['artworkUrl100'] as String?,
        episodeCount: (r['trackCount'] as num?)?.toInt(),
      );

  static String? _nonEmpty(Object? v) =>
      v is String && v.isNotEmpty ? v : null;
}
