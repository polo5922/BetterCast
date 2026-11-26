import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bettercast_core/bettercast_core.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'api_client.dart';
import 'providers.dart';

/// Firebase config passed at build time, so no google-services.json is
/// required to build:  --dart-define-from-file=firebase.json
class FirebaseConfig {
  static const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const appId = String.fromEnvironment('FIREBASE_APP_ID');
  static const senderId = String.fromEnvironment('FIREBASE_SENDER_ID');
  static const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static bool get configured => apiKey.isNotEmpty && appId.isNotEmpty;
}

/// New-episode notifications: FCM on Android, server-sent events on Windows
/// (while the app runs), both rendered with local notifications.
class NotificationsService {
  NotificationsService(this.ref);

  final Ref ref;
  final _local = FlutterLocalNotificationsPlugin();
  final _taps = StreamController<String>.broadcast();
  StreamSubscription<List<int>>? _sse;
  Timer? _sseRetry;
  bool _started = false;

  /// Podcast id of tapped notifications, for navigation.
  Stream<String> get taps => _taps.stream;

  static const _channelId = 'new_episodes';

  Future<void> init() async {
    await _local.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        windows: WindowsInitializationSettings(
          appName: 'BetterCast',
          appUserModelId: 'com.bettercast.BetterCast',
          guid: '6c4a9a2e-5d0f-4a8c-9a83-3f1e2b7c9d41',
        ),
      ),
      onDidReceiveNotificationResponse: (r) {
        if (r.payload != null) _taps.add(r.payload!);
      },
    );
    if (Platform.isAndroid) {
      await _local
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(const AndroidNotificationChannel(
            _channelId,
            'Nouveaux épisodes',
            description: 'Prévient quand un podcast suivi publie un épisode',
            importance: Importance.high,
          ));
      final launch = await _local.getNotificationAppLaunchDetails();
      final payload = launch?.notificationResponse?.payload;
      if (launch?.didNotificationLaunchApp == true && payload != null) {
        scheduleMicrotask(() => _taps.add(payload));
      }
    }
  }

  /// Call once signed in.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    if (Platform.isAndroid) {
      await _startFcm();
    } else if (Platform.isWindows) {
      await _registerDevice(null);
      _connectSse();
    }
  }

  Future<void> stop() async {
    _started = false;
    _sseRetry?.cancel();
    await _sse?.cancel();
    _sse = null;
  }

  Future<String> _deviceId() async {
    final db = ref.read(localDbProvider);
    var id = db.getKv('device_id');
    if (id == null) {
      id = const Uuid().v4();
      db.setKv('device_id', id);
    }
    return id;
  }

  Future<void> _registerDevice(String? pushToken) async {
    try {
      await ref.read(apiProvider).registerDevice(DeviceRegistration(
            deviceId: await _deviceId(),
            platform: Platform.isAndroid ? DevicePlatform.android : DevicePlatform.windows,
            pushToken: pushToken,
            name: Platform.localHostname,
          ));
    } on ApiException catch (e) {
      debugPrint('device registration failed: $e');
    }
  }

  // ---- Android: FCM ----

  Future<void> _startFcm() async {
    await _local
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    if (!FirebaseConfig.configured) {
      debugPrint('Firebase not configured: push notifications disabled');
      return;
    }
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: const FirebaseOptions(
            apiKey: FirebaseConfig.apiKey,
            appId: FirebaseConfig.appId,
            messagingSenderId: FirebaseConfig.senderId,
            projectId: FirebaseConfig.projectId,
          ),
        );
      }
      final fcm = FirebaseMessaging.instance;
      final token = await fcm.getToken();
      if (token != null) await _registerDevice(token);
      fcm.onTokenRefresh.listen(_registerDevice);
      // Background messages carry a `notification` block that Android shows
      // by itself; in foreground we render it ourselves.
      FirebaseMessaging.onMessage.listen((m) {
        if (m.data['type'] == 'new_episode') {
          unawaited(_showEpisode(NewEpisodeEvent.fromJson(m.data)));
        }
      });
      FirebaseMessaging.onMessageOpenedApp.listen((m) {
        final id = m.data['podcastId'];
        if (id is String) _taps.add(id);
      });
      final initial = await fcm.getInitialMessage();
      final id = initial?.data['podcastId'];
      if (id is String) scheduleMicrotask(() => _taps.add(id));
    } catch (e) {
      debugPrint('FCM init failed: $e');
    }
  }

  // ---- Windows: SSE ----

  void _connectSse() async {
    if (!_started) return;
    try {
      final stream = await ref.read(apiProvider).events();
      var buffer = '';
      _sse = stream.listen(
        (chunk) {
          buffer += utf8.decode(chunk, allowMalformed: true);
          int idx;
          while ((idx = buffer.indexOf('\n\n')) >= 0) {
            _onSseFrame(buffer.substring(0, idx));
            buffer = buffer.substring(idx + 2);
          }
        },
        onDone: _retrySse,
        onError: (_) => _retrySse(),
        cancelOnError: true,
      );
    } catch (_) {
      _retrySse();
    }
  }

  void _retrySse() {
    _sse = null;
    if (!_started) return;
    _sseRetry?.cancel();
    _sseRetry = Timer(const Duration(seconds: 15), _connectSse);
  }

  void _onSseFrame(String frame) {
    String? event;
    final data = StringBuffer();
    for (final line in const LineSplitter().convert(frame)) {
      if (line.startsWith('event:')) event = line.substring(6).trim();
      if (line.startsWith('data:')) data.write(line.substring(5).trim());
    }
    if (event != 'new_episode' || data.isEmpty) return;
    try {
      final e = NewEpisodeEvent.fromJson(jsonDecode(data.toString()) as Map<String, dynamic>);
      unawaited(_showEpisode(e));
      ref.invalidate(newReleasesProvider);
    } catch (_) {}
  }

  // ---- rendering ----

  Future<void> _showEpisode(NewEpisodeEvent e) async {
    final badges = [if (e.premium) 'Premium', if (e.hasVideo) 'Vidéo'].join(' · ');
    final body = [
      e.title,
      if (badges.isNotEmpty) badges,
      if (e.summary != null && e.summary!.isNotEmpty) e.summary!,
    ].join('\n');
    await _local.show(
      id: e.episodeId.hashCode & 0x7fffffff,
      title: e.podcastTitle,
      body: body,
      payload: e.podcastId,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'Nouveaux épisodes',
          importance: Importance.high,
          priority: Priority.high,
          styleInformation: BigTextStyleInformation(body, contentTitle: e.podcastTitle),
        ),
        windows: const WindowsNotificationDetails(),
      ),
    );
  }

  void dispose() {
    unawaited(stop());
    _taps.close();
  }
}

final notificationsProvider = Provider<NotificationsService>((ref) {
  final s = NotificationsService(ref);
  ref.onDispose(s.dispose);
  return s;
});
