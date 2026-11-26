import 'dart:async';
import 'dart:convert';

import 'package:bettercast_core/bettercast_core.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';

final _log = Logger('notify');

const eventsChannel = 'bettercast_events';

/// Fans out "new episode" events: FCM push for Android devices, and a
/// Postgres NOTIFY picked up by the API process for SSE (Windows clients).
class NotificationService {
  NotificationService(this._db, {String? fcmServiceAccountJson})
      : _fcmJson = fcmServiceAccountJson;

  final Pool _db;
  final String? _fcmJson;
  AutoRefreshingAuthClient? _fcm;
  String? _projectId;

  Future<void> _initFcm() async {
    if (_fcmJson == null || _fcm != null) return;
    final json = jsonDecode(_fcmJson) as Map<String, dynamic>;
    _projectId = json['project_id'] as String;
    _fcm = await clientViaServiceAccount(
      ServiceAccountCredentials.fromJson(json),
      ['https://www.googleapis.com/auth/firebase.messaging'],
    );
  }

  Future<void> notifyNewEpisodes(List<FeedItem> items) async {
    for (final item in items) {
      final rows = await _db.execute(
        Sql.named('SELECT s.user_id::text, d.device_id, d.push_token '
            'FROM subscriptions s '
            'LEFT JOIN devices d ON d.user_id = s.user_id '
            "AND d.platform = 'android' AND d.push_token IS NOT NULL "
            'WHERE s.podcast_id = @p AND s.notify'),
        parameters: {'p': item.podcast.id},
      );
      if (rows.isEmpty) continue;
      final users = {for (final r in rows) r[0] as String}.toList();
      final event = NewEpisodeEvent.fromItem(item);

      // SSE fan-out through the API process (8000-byte NOTIFY limit).
      for (var i = 0; i < users.length; i += 150) {
        final chunk = users.sublist(i, (i + 150).clamp(0, users.length));
        await _db.execute(
          Sql.named('SELECT pg_notify(@c, @p)'),
          parameters: {
            'c': eventsChannel,
            'p': jsonEncode({'episodeId': item.episode.id, 'users': chunk}),
          },
        );
      }

      final tokens = [
        for (final r in rows)
          if (r[2] != null) (user: r[0] as String, device: r[1] as String, token: r[2] as String),
      ];
      if (tokens.isNotEmpty) await _sendFcm(event, tokens);
    }
  }

  Future<void> _sendFcm(
    NewEpisodeEvent e,
    List<({String user, String device, String token})> targets,
  ) async {
    await _initFcm();
    final client = _fcm;
    if (client == null) return;
    final url = Uri.parse(
        'https://fcm.googleapis.com/v1/projects/$_projectId/messages:send');
    for (final t in targets) {
      final body = {
        'message': {
          'token': t.token,
          'data': e.toStringMap(),
          'notification': {
            'title': e.podcastTitle,
            'body': '${e.premium ? '⭐ ' : ''}${e.title}',
            'image': ?e.imageUrl,
          },
          'android': {
            'priority': 'high',
            'notification': {
              'channel_id': 'new_episodes',
              'tag': e.episodeId,
              'click_action': 'FLUTTER_NOTIFICATION_CLICK',
            },
          },
        },
      };
      try {
        final res = await client.post(url,
            headers: {'content-type': 'application/json'},
            body: jsonEncode(body));
        if (res.statusCode == 404 || res.statusCode == 400 &&
            res.body.contains('UNREGISTERED')) {
          await _db.execute(
            Sql.named('UPDATE devices SET push_token = NULL '
                'WHERE user_id = @u::uuid AND device_id = @d'),
            parameters: {'u': t.user, 'd': t.device},
          );
        } else if (res.statusCode >= 300) {
          _log.warning('FCM ${res.statusCode}: ${res.body}');
        }
      } on http.ClientException catch (err) {
        _log.warning('FCM send failed: $err');
      }
    }
  }

  void close() => _fcm?.close();
}

/// Keeps the SSE streams of connected clients and feeds them from the
/// Postgres channel the worker notifies on.
class EventHub {
  EventHub(this._databaseUrl, this._episodes);

  final String _databaseUrl;
  final Future<List<FeedItem>> Function(List<String> ids) _episodes;
  final _clients = <String, Set<StreamController<String>>>{};
  Connection? _conn;
  StreamSubscription<String>? _sub;

  Future<void> start() async {
    try {
      _conn = await Connection.openFromUrl(_databaseUrl);
      _sub = _conn!.channels[eventsChannel].listen(_onNotify);
    } catch (e) {
      _log.severe('EventHub could not listen: $e — retrying in 10s');
      Timer(const Duration(seconds: 10), start);
    }
  }

  Future<void> _onNotify(String payload) async {
    try {
      final j = jsonDecode(payload) as Map<String, dynamic>;
      final users = (j['users'] as List).cast<String>()
          .where(_clients.containsKey)
          .toList();
      if (users.isEmpty) return;
      final items = await _episodes([j['episodeId'] as String]);
      if (items.isEmpty) return;
      final data = jsonEncode(NewEpisodeEvent.fromItem(items.first).toJson());
      final frame = 'event: new_episode\ndata: $data\n\n';
      for (final u in users) {
        for (final c in _clients[u] ?? const <StreamController<String>>{}) {
          c.add(frame);
        }
      }
    } catch (e) {
      _log.warning('Bad event payload: $e');
    }
  }

  /// A text/event-stream body for [userId], with a heartbeat every 25 s.
  Stream<List<int>> subscribe(String userId) {
    late StreamController<String> c;
    Timer? heartbeat;
    c = StreamController<String>(
      onListen: () {
        _clients.putIfAbsent(userId, () => {}).add(c);
        c.add(': connected\n\nretry: 10000\n\n');
        heartbeat = Timer.periodic(
            const Duration(seconds: 25), (_) => c.add(': ping\n\n'));
      },
      onCancel: () {
        heartbeat?.cancel();
        _clients[userId]?.remove(c);
        if (_clients[userId]?.isEmpty ?? false) _clients.remove(userId);
      },
    );
    return c.stream.map(utf8.encode);
  }

  Future<void> close() async {
    await _sub?.cancel();
    await _conn?.close();
  }
}
