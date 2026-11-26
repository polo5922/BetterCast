import 'dart:async';

import 'package:bettercast_core/bettercast_core.dart';
import 'package:logging/logging.dart';

import 'feeds/podcast_repository.dart';
import 'services/notification_service.dart';

final _log = Logger('worker');

/// Periodically refreshes followed feeds and notifies subscribers of new
/// episodes.
class RefreshWorker {
  RefreshWorker(
    this._podcasts,
    this._notifications, {
    this.interval = const Duration(minutes: 20),
    this.tick = const Duration(seconds: 60),
    this.concurrency = 4,
  });

  final PodcastRepository _podcasts;
  final NotificationService _notifications;
  final Duration interval;
  final Duration tick;
  final int concurrency;
  bool _running = false;
  bool _stopped = false;

  Future<void> run() async {
    _log.info('Refresh worker started (interval ${interval.inMinutes} min)');
    while (!_stopped) {
      try {
        await runOnce();
      } catch (e, st) {
        _log.severe('Refresh pass failed', e, st);
      }
      await Future<void>.delayed(tick);
    }
  }

  void stop() => _stopped = true;

  /// One pass over the due podcasts. Returns the number of new episodes.
  Future<int> runOnce() async {
    if (_running) return 0;
    _running = true;
    var total = 0;
    try {
      while (true) {
        final due = await _podcasts.due(limit: concurrency * 5);
        if (due.isEmpty) break;
        for (var i = 0; i < due.length; i += concurrency) {
          final batch = due.skip(i).take(concurrency);
          final results = await Future.wait(
            batch.map((row) => _podcasts.refresh(row, interval: interval)),
          );
          for (final r in results) {
            if (r.podcast == null || r.newEpisodes.isEmpty) continue;
            total += r.newEpisodes.length;
            _log.info('${r.podcast!.title}: ${r.newEpisodes.length} new episode(s)');
            await _notifications.notifyNewEpisodes([
              for (final e in r.newEpisodes) FeedItem(episode: e, podcast: r.podcast!),
            ]);
          }
        }
        if (due.length < concurrency * 5) break;
      }
    } finally {
      _running = false;
    }
    return total;
  }
}
