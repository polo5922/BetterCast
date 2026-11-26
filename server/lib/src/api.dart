import 'dart:convert';

import 'package:bettercast_core/bettercast_core.dart';
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'auth/auth_service.dart';
import 'config.dart';
import 'feeds/podcast_repository.dart';
import 'http/json.dart';
import 'http/rate_limiter.dart';
import 'services/notification_service.dart';
import 'services/patreon_service.dart';
import 'services/search_service.dart';

final _log = Logger('api');

class Api {
  Api({
    required this.db,
    required this.config,
    required this.auth,
    required this.podcasts,
    required this.search,
    required this.patreon,
    required this.events,
  });

  final Pool db;
  final Config config;
  final AuthService auth;
  final PodcastRepository podcasts;
  final SearchService search;
  final PatreonService patreon;
  final EventHub? events;
  final _authLimiter = RateLimiter(maxHits: 10, window: const Duration(minutes: 1));

  Handler get handler {
    final public = Router()
      ..get('/health', (_) => jsonResponse({'ok': true}))
      ..post('/auth/register', _register)
      ..post('/auth/login', _login)
      ..post('/auth/refresh', _refresh)
      ..post('/auth/logout', _logout)
      ..get('/patreon/oauth/callback', _patreonCallback);

    final private = Router()
      ..get('/me', (Request r) async => jsonResponse((await auth.profile(r.userId)).toJson()))
      ..get('/search', _search)
      ..get('/discover/trending', _trending)
      ..post('/podcasts/lookup', _lookup)
      ..post('/podcasts/private', _addPrivate)
      ..get('/podcasts/<id>', _podcast)
      ..get('/podcasts/<id>/episodes', _podcastEpisodes)
      ..get('/subscriptions', _subscriptions)
      ..post('/subscriptions', _subscribe)
      ..patch('/subscriptions/<id>', _updateSubscription)
      ..delete('/subscriptions/<id>', _unsubscribe)
      ..post('/subscriptions/import-opml', _importOpml)
      ..get('/subscriptions/export-opml', _exportOpml)
      ..get('/feed/new', _newReleases)
      ..get('/episodes', _episodesByIds)
      ..get('/episode-states', _getStates)
      ..put('/episode-states', _putStates)
      ..post('/devices', _registerDevice)
      ..delete('/devices/<id>', _deleteDevice)
      ..get('/events', _events)
      ..get('/patreon/oauth/start', _patreonStart)
      ..get('/patreon/campaigns', _patreonCampaigns)
      ..post('/patreon/campaigns/sync', _patreonSync)
      ..post('/patreon/campaigns/<id>/feed', _patreonLink)
      ..delete('/patreon', _patreonDisconnect);

    final authed = const Pipeline().addMiddleware(auth.middleware()).addHandler(private.call);

    return const Pipeline()
        .addMiddleware(_errors())
        .addMiddleware(_cors())
        .addHandler(Cascade(statusCodes: [404, 405])
            .add(public.call)
            .add(authed)
            .handler);
  }

  // ---- middleware ----------------------------------------------------------

  Middleware _errors() => (inner) => (req) async {
        try {
          return await inner(req);
        } on ApiException catch (e) {
          return jsonResponse(ApiError(e.code, e.message).toJson(), status: e.status);
        } on FeedParseException catch (e) {
          return jsonResponse(const ApiError('invalid_feed', '').toJson()
            ..['message'] = e.message, status: 422);
        } catch (e, st) {
          _log.severe('Unhandled error on ${req.method} ${req.url}', e, st);
          return jsonResponse(
              const ApiError('internal', 'Internal server error').toJson(),
              status: 500);
        }
      };

  Middleware _cors() => (inner) => (req) async {
        const headers = {
          'access-control-allow-origin': '*',
          'access-control-allow-headers': 'authorization, content-type',
          'access-control-allow-methods': 'GET, POST, PUT, PATCH, DELETE, OPTIONS',
        };
        if (req.method == 'OPTIONS') return Response.ok(null, headers: headers);
        final res = await inner(req);
        return res.change(headers: headers);
      };

  void _limit(Request req) {
    final ip = req.headers['x-forwarded-for']?.split(',').first.trim() ??
        (req.context['shelf.io.connection_info'] as dynamic)?.remoteAddress?.address as String? ??
        'unknown';
    if (!_authLimiter.hit(ip)) {
      throw ApiException(429, 'rate_limited', 'Too many attempts, retry later');
    }
  }

  // ---- auth ----------------------------------------------------------------

  Future<Response> _register(Request req) async {
    _limit(req);
    if (!config.allowRegistration) {
      throw ApiException(403, 'registration_closed', 'Registration is disabled');
    }
    final j = await readJson(req);
    final res = await auth.register(
      field<String>(j, 'email'),
      field<String>(j, 'password'),
      displayName: j['displayName'] as String?,
    );
    return jsonResponse(res.toJson(), status: 201);
  }

  Future<Response> _login(Request req) async {
    _limit(req);
    final j = await readJson(req);
    final res = await auth.login(field<String>(j, 'email'), field<String>(j, 'password'));
    return jsonResponse(res.toJson());
  }

  Future<Response> _refresh(Request req) async {
    final j = await readJson(req);
    return jsonResponse((await auth.refresh(field<String>(j, 'refreshToken'))).toJson());
  }

  Future<Response> _logout(Request req) async {
    final j = await readJson(req);
    await auth.logout(field<String>(j, 'refreshToken'));
    return Response(204);
  }

  // ---- discovery -----------------------------------------------------------

  Future<Response> _search(Request req) async {
    final q = req.url.queryParameters['q'] ?? '';
    if (q.trim().length < 2) return jsonResponse([]);
    final results = await search.search(q);
    return jsonResponse(results.map((r) => r.toJson()).toList());
  }

  Future<Response> _trending(Request req) async {
    final q = req.url.queryParameters;
    final results = await search.trending(
      country: q['country'] ?? q['lang'] ?? 'fr',
      genre: q['genre'],
    );
    return jsonResponse(results.map((r) => r.toJson()).toList());
  }

  Future<Response> _lookup(Request req) async {
    final j = await readJson(req);
    final podcast = await podcasts.ensurePublic(field<String>(j, 'feedUrl'));
    return _detail(req.userId, podcast);
  }

  /// Any private RSS feed (Patreon, Supercast, Supporting Cast...).
  Future<Response> _addPrivate(Request req) async {
    final j = await readJson(req);
    final podcast = await podcasts.upsertPrivate(
      userId: req.userId,
      feedUrl: field<String>(j, 'feedUrl'),
      source: PodcastSource.rss,
    );
    await _subscribeTo(req.userId, podcast.id);
    return _detail(req.userId, podcast);
  }

  Future<Response> _podcast(Request req, String id) async {
    final podcast = await podcasts.get(id, userId: req.userId);
    return _detail(req.userId, podcast);
  }

  Future<Response> _detail(String userId, Podcast podcast) async {
    final episodes = await podcasts.episodes(podcast.id, limit: 100);
    final sub = await db.execute(
      Sql.named('SELECT 1 FROM subscriptions WHERE user_id = @u::uuid AND podcast_id = @p'),
      parameters: {'u': userId, 'p': podcast.id},
    );
    return jsonResponse(PodcastDetail(
      podcast: podcast,
      episodes: episodes,
      subscribed: sub.isNotEmpty,
    ).toJson());
  }

  Future<Response> _podcastEpisodes(Request req, String id) async {
    await podcasts.get(id, userId: req.userId); // access check
    final q = req.url.queryParameters;
    final list = await podcasts.episodes(
      id,
      limit: int.tryParse(q['limit'] ?? '') ?? 50,
      offset: int.tryParse(q['offset'] ?? '') ?? 0,
    );
    return jsonResponse(list.map((e) => e.toJson()).toList());
  }

  // ---- subscriptions -------------------------------------------------------

  Future<Response> _subscriptions(Request req) async {
    final rows = await db.execute(
      Sql.named('SELECT p.data, s.subscribed_at, s.notify FROM subscriptions s '
          'JOIN podcasts p ON p.id = s.podcast_id WHERE s.user_id = @u::uuid '
          'ORDER BY lower(p.title)'),
      parameters: {'u': req.userId},
    );
    return jsonResponse([
      for (final r in rows)
        Subscription(
          podcast: Podcast.fromJson((r[0] as Map).cast()),
          subscribedAt: r[1] as DateTime,
          notify: r[2] as bool,
        ).toJson(),
    ]);
  }

  Future<void> _subscribeTo(String userId, String podcastId, {bool notify = true}) =>
      db.execute(
        Sql.named('INSERT INTO subscriptions(user_id, podcast_id, notify) '
            'VALUES (@u::uuid, @p, @n) ON CONFLICT (user_id, podcast_id) '
            'DO UPDATE SET notify = EXCLUDED.notify'),
        parameters: {'u': userId, 'p': podcastId, 'n': notify},
      );

  /// Body: `{"podcastId": "..."}` (already known) or `{"feedUrl": "..."}`.
  Future<Response> _subscribe(Request req) async {
    final j = await readJson(req);
    final Podcast podcast;
    if (j['feedUrl'] is String) {
      podcast = await podcasts.ensurePublic(j['feedUrl'] as String);
    } else {
      podcast = await podcasts.get(field<String>(j, 'podcastId'), userId: req.userId);
    }
    await _subscribeTo(req.userId, podcast.id, notify: j['notify'] as bool? ?? true);
    return jsonResponse(Subscription(
      podcast: podcast,
      subscribedAt: DateTime.now().toUtc(),
      notify: j['notify'] as bool? ?? true,
    ).toJson(), status: 201);
  }

  Future<Response> _updateSubscription(Request req, String id) async {
    final j = await readJson(req);
    final rows = await db.execute(
      Sql.named('UPDATE subscriptions SET notify = @n '
          'WHERE user_id = @u::uuid AND podcast_id = @p RETURNING 1'),
      parameters: {'u': req.userId, 'p': id, 'n': field<bool>(j, 'notify')},
    );
    if (rows.isEmpty) throw ApiException.notFound();
    return Response(204);
  }

  Future<Response> _unsubscribe(Request req, String id) async {
    await db.execute(
      Sql.named('DELETE FROM subscriptions WHERE user_id = @u::uuid AND podcast_id = @p'),
      parameters: {'u': req.userId, 'p': id},
    );
    return Response(204);
  }

  Future<Response> _importOpml(Request req) async {
    final entries = parseOpml(await req.readAsString());
    var imported = 0;
    final failed = <String>[];
    // Sequential on purpose: be gentle with feed hosts.
    for (final e in entries.take(500)) {
      try {
        final p = await podcasts.ensurePublic(e.feedUrl);
        await _subscribeTo(req.userId, p.id);
        imported++;
      } catch (_) {
        failed.add(e.feedUrl);
      }
    }
    return jsonResponse({'imported': imported, 'failed': failed});
  }

  Future<Response> _exportOpml(Request req) async {
    final rows = await db.execute(
      Sql.named('SELECT p.feed_url, p.title FROM subscriptions s '
          'JOIN podcasts p ON p.id = s.podcast_id '
          'WHERE s.user_id = @u::uuid AND p.feed_url IS NOT NULL ORDER BY p.title'),
      parameters: {'u': req.userId},
    );
    final xml = buildOpml([
      for (final r in rows) OpmlEntry(feedUrl: r[0] as String, title: r[1] as String),
    ]);
    return Response.ok(xml, headers: {
      'content-type': 'text/x-opml; charset=utf-8',
      'content-disposition': 'attachment; filename="bettercast.opml"',
    });
  }

  // ---- feed & states -------------------------------------------------------

  /// Latest episodes across all subscriptions. `?before=<iso date>` paginates.
  Future<Response> _newReleases(Request req) async {
    final q = req.url.queryParameters;
    final before = parseDate(q['before']) ?? DateTime.now().toUtc().add(const Duration(days: 1));
    final limit = (int.tryParse(q['limit'] ?? '') ?? 50).clamp(1, 200);
    final rows = await db.execute(
      Sql.named('SELECT e.data, p.data FROM subscriptions s '
          'JOIN episodes e ON e.podcast_id = s.podcast_id '
          'JOIN podcasts p ON p.id = s.podcast_id '
          'WHERE s.user_id = @u::uuid AND e.published_at < @b '
          'ORDER BY e.published_at DESC LIMIT @l'),
      parameters: {'u': req.userId, 'b': before, 'l': limit},
    );
    return jsonResponse([
      for (final r in rows)
        FeedItem(
          episode: Episode.fromJson((r[0] as Map).cast()),
          podcast: Podcast.fromJson((r[1] as Map).cast()),
        ).toJson(),
    ]);
  }

  /// `?ids=a,b,c` — used for liked / in-progress lists.
  Future<Response> _episodesByIds(Request req) async {
    final ids = (req.url.queryParameters['ids'] ?? '')
        .split(',')
        .where((s) => s.isNotEmpty)
        .take(200)
        .toList();
    final items = await podcasts.episodesByIds(ids);
    // Only public podcasts or the user's own private ones.
    final allowed = await db.execute(
      Sql.named('SELECT id FROM podcasts WHERE id = ANY(@ids) '
          'AND (owner_user_id IS NULL OR owner_user_id = @u::uuid)'),
      parameters: {
        'ids': TypedValue(Type.textArray, {for (final i in items) i.podcast.id}.toList()),
        'u': req.userId,
      },
    );
    final ok = {for (final r in allowed) r[0] as String};
    return jsonResponse([
      for (final i in items)
        if (ok.contains(i.podcast.id)) i.toJson(),
    ]);
  }

  /// `?since=<iso date>`: states changed on the server after that instant.
  Future<Response> _getStates(Request req) async {
    final since = parseDate(req.url.queryParameters['since']) ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    final rows = await db.execute(
      Sql.named('SELECT episode_id, podcast_id, position_ms, played, liked, '
          'updated_at, synced_at FROM episode_states '
          'WHERE user_id = @u::uuid AND synced_at > @s ORDER BY synced_at'),
      parameters: {'u': req.userId, 's': since},
    );
    final serverTime = rows.isEmpty ? since : rows.last[6] as DateTime;
    return jsonResponse({
      'serverTime': dateToJson(serverTime),
      'states': [
        for (final r in rows)
          EpisodeState(
            episodeId: r[0] as String,
            podcastId: r[1] as String?,
            position: Duration(milliseconds: r[2] as int),
            played: r[3] as bool,
            liked: r[4] as bool,
            updatedAt: r[5] as DateTime,
          ).toJson(),
      ],
    });
  }

  /// Body: `[EpisodeState, ...]`. Last-write-wins on `updatedAt`.
  Future<Response> _putStates(Request req) async {
    final body = jsonDecode(await req.readAsString());
    if (body is! List) throw ApiException.badRequest('Expected a JSON array');
    final states = [
      for (final s in body.whereType<Map>().take(1000))
        EpisodeState.fromJson(s.cast()),
    ];
    if (states.isEmpty) return jsonResponse({'accepted': 0});
    final rows = await db.execute(
      Sql.named('INSERT INTO episode_states(user_id, episode_id, podcast_id, '
          'position_ms, played, liked, updated_at) '
          'SELECT @u::uuid, x.episode_id, x.podcast_id, x.position_ms, x.played, '
          'x.liked, x.updated_at FROM jsonb_to_recordset(@rows::jsonb) AS x('
          'episode_id text, podcast_id text, position_ms bigint, played boolean, '
          'liked boolean, updated_at timestamptz) '
          'ON CONFLICT (user_id, episode_id) DO UPDATE SET '
          'podcast_id = COALESCE(EXCLUDED.podcast_id, episode_states.podcast_id), '
          'position_ms = EXCLUDED.position_ms, played = EXCLUDED.played, '
          'liked = EXCLUDED.liked, updated_at = EXCLUDED.updated_at, synced_at = now() '
          'WHERE EXCLUDED.updated_at > episode_states.updated_at RETURNING 1'),
      parameters: {
        'u': req.userId,
        'rows': jsonEncode([
          for (final s in states)
            {
              'episode_id': s.episodeId,
              'podcast_id': s.podcastId,
              'position_ms': s.position.inMilliseconds,
              'played': s.played,
              'liked': s.liked,
              'updated_at': dateToJson(s.updatedAt),
            },
        ]),
      },
    );
    return jsonResponse({'accepted': rows.length});
  }

  // ---- devices & events ----------------------------------------------------

  Future<Response> _registerDevice(Request req) async {
    final d = DeviceRegistration.fromJson(await readJson(req));
    await db.execute(
      Sql.named('INSERT INTO devices(user_id, device_id, platform, push_token, name) '
          'VALUES (@u::uuid, @d, @p, @t, @n) ON CONFLICT (user_id, device_id) DO UPDATE '
          'SET platform = EXCLUDED.platform, push_token = EXCLUDED.push_token, '
          'name = EXCLUDED.name, updated_at = now()'),
      parameters: {
        'u': req.userId,
        'd': d.deviceId,
        'p': d.platform.name,
        't': d.pushToken,
        'n': d.name,
      },
    );
    return Response(204);
  }

  Future<Response> _deleteDevice(Request req, String id) async {
    await db.execute(
      Sql.named('DELETE FROM devices WHERE user_id = @u::uuid AND device_id = @d'),
      parameters: {'u': req.userId, 'd': id},
    );
    return Response(204);
  }

  Response _events(Request req) {
    final hub = events;
    if (hub == null) throw ApiException(503, 'events_disabled', 'Events unavailable');
    return Response.ok(
      hub.subscribe(req.userId),
      headers: {
        'content-type': 'text/event-stream',
        'cache-control': 'no-cache',
        'x-accel-buffering': 'no',
      },
      context: {'shelf.io.buffer_output': false},
    );
  }

  // ---- patreon -------------------------------------------------------------

  Future<Response> _patreonStart(Request req) async =>
      jsonResponse({'url': (await patreon.authorizeUrl(req.userId)).toString()});

  Future<Response> _patreonCallback(Request req) async {
    final q = req.url.queryParameters;
    var ok = false;
    String? message;
    if (q['error'] != null) {
      message = q['error_description'] ?? q['error'];
    } else {
      try {
        await patreon.handleCallback(code: q['code'] ?? '', state: q['state'] ?? '');
        ok = true;
      } on ApiException catch (e) {
        message = e.message;
      }
    }
    final target = '${config.appRedirectUri}?status=${ok ? 'ok' : 'error'}';
    final title = ok ? 'Patreon connecté' : 'Échec de la connexion Patreon';
    final text = ok
        ? 'Tu peux revenir dans BetterCast.'
        : const HtmlEscape().convert(message ?? 'Erreur inconnue');
    return Response.ok('''<!doctype html>
<html lang="fr"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>BetterCast</title>
<style>body{font-family:system-ui,sans-serif;display:grid;place-items:center;min-height:90vh;margin:0;background:#111;color:#eee;text-align:center}a{color:#ff7a59}</style>
</head><body><main><h1>$title</h1><p>$text</p>
<p><a href="$target">Ouvrir BetterCast</a></p></main>
<script>location.href=${jsonEncode(target)};</script>
</body></html>''', headers: {'content-type': 'text/html; charset=utf-8'});
  }

  Future<Response> _patreonCampaigns(Request req) async => jsonResponse(
      (await patreon.campaignsOf(req.userId)).map((c) => c.toJson()).toList());

  Future<Response> _patreonSync(Request req) async => jsonResponse(
      (await patreon.syncMemberships(req.userId)).map((c) => c.toJson()).toList());

  Future<Response> _patreonLink(Request req, String id) async {
    final j = await readJson(req);
    final podcast = await patreon.linkFeed(req.userId, id, field<String>(j, 'feedUrl'));
    return _detail(req.userId, podcast);
  }

  Future<Response> _patreonDisconnect(Request req) async {
    await patreon.disconnect(req.userId);
    return Response(204);
  }
}
