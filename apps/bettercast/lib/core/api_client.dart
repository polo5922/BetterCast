import 'dart:async';
import 'dart:convert';

import 'package:bettercast_core/bettercast_core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stores the server URL and the JWT pair.
class TokenStore {
  TokenStore([FlutterSecureStorage? storage])
      : _s = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _s;

  AuthTokens? tokens;
  String? serverUrl;

  Future<void> load() async {
    serverUrl = await _s.read(key: 'server_url');
    final raw = await _s.read(key: 'tokens');
    if (raw != null) {
      try {
        tokens = AuthTokens.fromJson(jsonDecode(raw) as Json);
      } catch (_) {
        tokens = null;
      }
    }
  }

  Future<void> save(String server, AuthTokens t) async {
    serverUrl = server;
    tokens = t;
    await _s.write(key: 'server_url', value: server);
    await _s.write(key: 'tokens', value: jsonEncode(t.toJson()));
  }

  Future<void> clear() async {
    tokens = null;
    await _s.delete(key: 'tokens');
  }
}

class ApiException implements Exception {
  ApiException(this.status, this.code, this.message);
  final int? status;
  final String code;
  final String message;

  bool get isOffline => status == null;

  factory ApiException.from(Object e) {
    if (e is ApiException) return e;
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map && data['error'] is String) {
        return ApiException(e.response?.statusCode, data['error'] as String,
            data['message'] as String? ?? data['error'] as String);
      }
      if (e.response == null) {
        return ApiException(null, 'offline', 'Serveur injoignable');
      }
      return ApiException(e.response?.statusCode, 'http',
          'Erreur ${e.response?.statusCode}');
    }
    return ApiException(null, 'unknown', '$e');
  }

  @override
  String toString() => message;
}

/// Typed client for the BetterCast server. Refreshes the access token
/// transparently and calls [onSessionExpired] when the refresh token is dead.
class ApiClient {
  ApiClient(this.store, {this.onSessionExpired}) {
    _dio.interceptors.add(QueuedInterceptorsWrapper(
      onRequest: (o, h) async {
        o.baseUrl = store.serverUrl ?? '';
        final t = store.tokens;
        if (t != null && o.extra['noAuth'] != true) {
          if (t.expiresAt.isBefore(DateTime.now().add(const Duration(seconds: 30)))) {
            await _refresh();
          }
          final cur = store.tokens;
          if (cur != null) o.headers['authorization'] = 'Bearer ${cur.accessToken}';
        }
        h.next(o);
      },
      onError: (e, h) async {
        final o = e.requestOptions;
        if (e.response?.statusCode == 401 &&
            o.extra['noAuth'] != true &&
            o.extra['retried'] != true &&
            store.tokens != null) {
          if (await _refresh()) {
            o.extra['retried'] = true;
            o.headers['authorization'] = 'Bearer ${store.tokens!.accessToken}';
            try {
              return h.resolve(await _dio.fetch(o));
            } on DioException catch (e2) {
              return h.next(e2);
            }
          }
        }
        h.next(e);
      },
    ));
  }

  final TokenStore store;
  void Function()? onSessionExpired;
  final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 60),
  ));
  Future<bool>? _refreshing;

  Future<bool> _refresh() => _refreshing ??= () async {
        try {
          final t = store.tokens;
          if (t == null) return false;
          final res = await Dio(BaseOptions(baseUrl: store.serverUrl!))
              .post<Map<String, dynamic>>('/auth/refresh',
                  data: {'refreshToken': t.refreshToken});
          await store.save(store.serverUrl!, AuthTokens.fromJson(res.data!));
          return true;
        } on DioException catch (e) {
          if (e.response?.statusCode == 401) {
            await store.clear();
            onSessionExpired?.call();
          }
          return false;
        } finally {
          _refreshing = null;
        }
      }();

  Future<T> _call<T>(Future<Response<dynamic>> Function() f, T Function(dynamic) map) async {
    try {
      final r = await f();
      return map(r.data);
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  List<T> _list<T>(dynamic d, T Function(Json) f) =>
      [for (final x in d as List) f((x as Map).cast())];

  // ---- auth ----

  Future<AuthResponse> login(String server, String email, String password,
      {bool register = false, String? displayName}) async {
    store.serverUrl = server;
    final res = await _call(
      () => _dio.post('/auth/${register ? 'register' : 'login'}',
          data: {
            'email': email,
            'password': password,
            'displayName': ?displayName,
          },
          options: Options(extra: {'noAuth': true})),
      (d) => AuthResponse.fromJson((d as Map).cast()),
    );
    await store.save(server, res.tokens);
    return res;
  }

  Future<void> logout() async {
    final t = store.tokens;
    if (t != null) {
      try {
        await _dio.post('/auth/logout',
            data: {'refreshToken': t.refreshToken},
            options: Options(extra: {'noAuth': true}));
      } catch (_) {}
    }
    await store.clear();
  }

  Future<UserProfile> me() =>
      _call(() => _dio.get('/me'), (d) => UserProfile.fromJson((d as Map).cast()));

  // ---- discovery ----

  Future<List<SearchResult>> search(String q) => _call(
      () => _dio.get('/search', queryParameters: {'q': q}),
      (d) => _list(d, SearchResult.fromJson));

  Future<List<SearchResult>> trending({String country = 'fr', String? genre}) => _call(
      () => _dio.get('/discover/trending',
          queryParameters: {'country': country, 'genre': ?genre}),
      (d) => _list(d, SearchResult.fromJson));

  Future<PodcastDetail> podcast(String id) => _call(
      () => _dio.get('/podcasts/$id'), (d) => PodcastDetail.fromJson((d as Map).cast()));

  Future<PodcastDetail> lookup(String feedUrl) => _call(
      () => _dio.post('/podcasts/lookup', data: {'feedUrl': feedUrl}),
      (d) => PodcastDetail.fromJson((d as Map).cast()));

  Future<PodcastDetail> addPrivateFeed(String feedUrl) => _call(
      () => _dio.post('/podcasts/private', data: {'feedUrl': feedUrl}),
      (d) => PodcastDetail.fromJson((d as Map).cast()));

  Future<List<Episode>> episodes(String podcastId, {int limit = 50, int offset = 0}) =>
      _call(
          () => _dio.get('/podcasts/$podcastId/episodes',
              queryParameters: {'limit': limit, 'offset': offset}),
          (d) => _list(d, Episode.fromJson));

  // ---- library ----

  Future<List<Subscription>> subscriptions() =>
      _call(() => _dio.get('/subscriptions'), (d) => _list(d, Subscription.fromJson));

  Future<void> subscribe(String podcastId) =>
      _call(() => _dio.post('/subscriptions', data: {'podcastId': podcastId}), (_) {});

  Future<void> unsubscribe(String podcastId) =>
      _call(() => _dio.delete('/subscriptions/$podcastId'), (_) {});

  Future<void> setNotify(String podcastId, bool notify) => _call(
      () => _dio.patch('/subscriptions/$podcastId', data: {'notify': notify}), (_) {});

  Future<({int imported, List<String> failed})> importOpml(String opml) => _call(
      () => _dio.post('/subscriptions/import-opml',
          data: opml,
          options: Options(
            contentType: 'text/x-opml',
            receiveTimeout: const Duration(minutes: 10),
          )),
      (d) => (
            imported: (d as Map)['imported'] as int,
            failed: (d['failed'] as List).cast<String>(),
          ));

  Future<String> exportOpml() => _call(
      () => _dio.get('/subscriptions/export-opml',
          options: Options(responseType: ResponseType.plain)),
      (d) => d as String);

  Future<List<FeedItem>> newReleases({DateTime? before, int limit = 50}) => _call(
      () => _dio.get('/feed/new', queryParameters: {
            'limit': limit,
            if (before != null) 'before': before.toUtc().toIso8601String(),
          }),
      (d) => _list(d, FeedItem.fromJson));

  Future<List<FeedItem>> episodesByIds(List<String> ids) async {
    if (ids.isEmpty) return [];
    final out = <FeedItem>[];
    for (var i = 0; i < ids.length; i += 150) {
      out.addAll(await _call(
          () => _dio.get('/episodes',
              queryParameters: {'ids': ids.skip(i).take(150).join(',')}),
          (d) => _list(d, FeedItem.fromJson)));
    }
    return out;
  }

  // ---- sync ----

  Future<({DateTime serverTime, List<EpisodeState> states})> pullStates(DateTime since) =>
      _call(
          () => _dio.get('/episode-states',
              queryParameters: {'since': since.toUtc().toIso8601String()}),
          (d) => (
                serverTime: parseDate((d as Map)['serverTime']) ?? since,
                states: _list(d['states'], EpisodeState.fromJson),
              ));

  Future<void> pushStates(List<EpisodeState> states) => _call(
      () => _dio.put('/episode-states', data: [for (final s in states) s.toJson()]),
      (_) {});

  Future<void> registerDevice(DeviceRegistration d) =>
      _call(() => _dio.post('/devices', data: d.toJson()), (_) {});

  /// Raw SSE byte stream (Windows live notifications).
  Future<Stream<List<int>>> events() async {
    try {
      final r = await _dio.get<ResponseBody>('/events',
          options: Options(
            responseType: ResponseType.stream,
            receiveTimeout: const Duration(minutes: 2),
            headers: {'accept': 'text/event-stream'},
          ));
      return r.data!.stream;
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  // ---- patreon ----

  Future<Uri> patreonAuthorizeUrl() => _call(() => _dio.get('/patreon/oauth/start'),
      (d) => Uri.parse((d as Map)['url'] as String));

  Future<List<PatreonCampaign>> patreonCampaigns({bool sync = false}) => _call(
      () => sync ? _dio.post('/patreon/campaigns/sync') : _dio.get('/patreon/campaigns'),
      (d) => _list(d, PatreonCampaign.fromJson));

  Future<PodcastDetail> linkPatreonFeed(String campaignId, String feedUrl) => _call(
      () => _dio.post('/patreon/campaigns/$campaignId/feed', data: {'feedUrl': feedUrl}),
      (d) => PodcastDetail.fromJson((d as Map).cast()));

  Future<void> disconnectPatreon() => _call(() => _dio.delete('/patreon'), (_) {});
}
