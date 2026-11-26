import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:media_kit/media_kit.dart';

import 'app.dart';
import 'core/api_client.dart';
import 'core/auto_downloads.dart';
import 'core/local_db.dart';
import 'core/notifications.dart';
import 'core/providers.dart';
import 'player/audio_handler.dart';
import 'player/player_providers.dart';
import 'player/windows_media.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await initializeDateFormatting('fr_FR');

  final store = TokenStore();
  await store.load();
  final db = LocalDb.open();

  final container = ProviderContainer(overrides: [
    localDbProvider.overrideWithValue(await db),
    tokenStoreProvider.overrideWithValue(store),
  ]);
  final player = container.read(playerProvider);

  // System media controls.
  if (Platform.isAndroid) {
    await AudioService.init(
      builder: () => BetterCastAudioHandler(player, AppMediaLibrary(container)),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.bettercast.playback',
        androidNotificationChannelName: 'Lecture',
        androidNotificationIcon: 'mipmap/ic_launcher',
        androidStopForegroundOnPause: true,
      ),
    );
  } else if (Platform.isWindows) {
    try {
      await WindowsMediaControls.initialize();
      WindowsMediaControls(player).start();
    } catch (e) {
      debugPrint('SMTC init failed: $e');
    }
  }

  final notifications = container.read(notificationsProvider);
  await notifications.init();

  // Start push/SSE + sync whenever a user is signed in.
  void onSession(bool signedIn) {
    if (signedIn) {
      unawaited(notifications.start());
      unawaited(container
          .read(episodeStatesProvider.notifier)
          .sync()
          .then((_) => container.read(autoDownloadsProvider.notifier).run()));
    } else {
      unawaited(notifications.stop());
      unawaited(player.stop());
    }
  }

  container.listen<bool>(sessionProvider.select((s) => s.signedIn), (prev, next) {
    if (prev != next) onSession(next);
  }, fireImmediately: true);

  AppLifecycleListener(
    onResume: () {
      if (container.read(sessionProvider).signedIn) {
        unawaited(container
            .read(episodeStatesProvider.notifier)
            .sync()
            .then((_) => container.read(autoDownloadsProvider.notifier).run()));
      }
      unawaited(player.setBackgroundMode(false));
    },
    // Only phones drop video in the background; a minimized desktop window keeps it.
    onHide: Platform.isAndroid ? () => unawaited(player.setBackgroundMode(true)) : null,
  );

  runApp(UncontrolledProviderScope(container: container, child: const BetterCastApp()));
}
