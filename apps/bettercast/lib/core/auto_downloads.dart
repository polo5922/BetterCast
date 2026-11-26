import 'dart:async';

import 'package:bettercast_core/bettercast_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'downloads.dart';
import 'local_db.dart';
import 'providers.dart';

/// Per-podcast auto-download: keeps the latest 1 or 2 episodes on the device.
/// Stored locally (downloads are per device), keyed `autodl:<podcastId>`.
class AutoDownloads extends Notifier<Map<String, int>> {
  static const _prefix = 'autodl:';
  static const _handled = 'autodl_ep:'; // episodes already taken care of
  bool _running = false;

  LocalDb get _db => ref.read(localDbProvider);

  @override
  Map<String, int> build() => {
        for (final e in _db.kvWithPrefix(_prefix).entries)
          e.key.substring(_prefix.length): int.tryParse(e.value) ?? 0,
      };

  int countFor(String podcastId) => state[podcastId] ?? 0;

  bool get wifiOnly => _db.getKv('autodl_wifi') != '0';
  set wifiOnly(bool v) => _db.setKv('autodl_wifi', v ? '1' : '0');

  void set(String podcastId, int count) {
    _db.setKv('$_prefix$podcastId', count > 0 ? '$count' : null);
    state = {...state, podcastId: count}..removeWhere((_, v) => v <= 0);
    if (count > 0) unawaited(run(only: podcastId));
  }

  /// Downloads the latest episodes of every podcast that opted in, and removes
  /// auto-downloaded episodes that have fallen out of the window.
  Future<void> run({String? only}) async {
    if (_running || !ref.read(sessionProvider).signedIn) return;
    _running = true;
    try {
      Set<String> subscribed;
      try {
        subscribed = {for (final s in await ref.read(subscriptionsProvider.future)) s.podcast.id};
      } catch (_) {
        subscribed = const {};
      }
      for (final MapEntry(key: podcastId, value: count) in state.entries) {
        if (only != null && podcastId != only) continue;
        if (count <= 0 || (subscribed.isNotEmpty && !subscribed.contains(podcastId))) continue;
        try {
          await _runFor(podcastId, count);
        } catch (_) {
          // Offline or feed error: next run will retry.
        }
      }
    } finally {
      _running = false;
    }
  }

  Future<void> _runFor(String podcastId, int count) async {
    ref.invalidate(podcastDetailProvider(podcastId));
    final d = await ref.read(podcastDetailProvider(podcastId).future);
    final episodes = [...d.episodes]..sort((a, b) =>
        (b.publishedAt ?? DateTime(0)).compareTo(a.publishedAt ?? DateTime(0)));
    final latest = episodes.take(count).toList();
    final keep = {for (final e in latest) e.id};
    final downloads = ref.read(downloadsProvider.notifier);
    final states = ref.read(episodeStatesProvider);

    // Drop auto-downloads that are no longer among the latest, unless started.
    for (final rec in ref.read(downloadsProvider).values.toList()) {
      final e = rec.item.episode;
      if (e.podcastId != podcastId || keep.contains(e.id)) continue;
      if (_db.getKv('$_handled${e.id}') != 'auto') continue;
      if (states[e.id]?.inProgress ?? false) continue;
      await downloads.remove(e.id);
    }

    for (final e in latest) {
      if (_db.getKv('$_handled${e.id}') != null) continue; // done, or deleted by the user
      if (downloads.of(e.id) != null || (states[e.id]?.played ?? false)) {
        _db.setKv('$_handled${e.id}', 'skip');
        continue;
      }
      _db.setKv('$_handled${e.id}', 'auto');
      unawaited(downloads.download(FeedItem(episode: e, podcast: d.podcast), wifiOnly: wifiOnly));
    }
  }
}

final autoDownloadsProvider =
    NotifierProvider<AutoDownloads, Map<String, int>>(AutoDownloads.new);
