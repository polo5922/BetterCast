import 'package:bettercast_core/bettercast_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../core/connectivity.dart';
import '../core/downloads.dart';
import '../core/providers.dart';
import 'audio_handler.dart';
import 'player_controller.dart';

class _Store implements PlaybackStore {
  _Store(this.ref);
  final Ref ref;

  @override
  Duration resumePosition(Episode e) {
    final s = ref.read(episodeStatesProvider)[e.id];
    if (s == null || s.played) return Duration.zero;
    // Rewind a little so the listener gets context back.
    final p = s.position - const Duration(seconds: 3);
    return p.isNegative ? Duration.zero : p;
  }

  @override
  void savePosition(Episode e, Duration position, Duration? duration) =>
      ref.read(episodeStatesProvider.notifier).savePosition(e, position, duration: duration);

  @override
  void markPlayed(Episode e) => ref.read(episodeStatesProvider.notifier).setPlayed(e, true);

  @override
  String? localPath(Episode e, MediaVariant v) =>
      ref.read(downloadsProvider.notifier).localPath(e.id, v.url);

  @override
  bool get online => ref.read(onlineProvider);
}

final playerProvider = ChangeNotifierProvider<PlayerController>((ref) {
  return PlayerController(_Store(ref));
});

/// Data source of the Android Auto browse tree.
class AppMediaLibrary implements MediaLibrary {
  AppMediaLibrary(this.container);
  final ProviderContainer container;

  @override
  Future<List<FeedItem>> newReleases() => container.read(newReleasesProvider.future);

  @override
  Future<List<FeedItem>> inProgress() => container.read(inProgressEpisodesProvider.future);

  @override
  Future<List<FeedItem>> liked() => container.read(likedEpisodesProvider.future);

  @override
  Future<List<FeedItem>> downloaded() async => [
        for (final d in container.read(downloadsProvider).values)
          if (d.isComplete) d.item,
      ];

  @override
  Future<List<Podcast>> subscriptions() async =>
      [for (final s in await container.read(subscriptionsProvider.future)) s.podcast];

  @override
  Future<List<FeedItem>> podcastEpisodes(String podcastId) async {
    final d = await container.read(podcastDetailProvider(podcastId).future);
    return [for (final e in d.episodes) FeedItem(episode: e, podcast: d.podcast)];
  }

  @override
  Future<List<SearchResult>> search(String query) =>
      container.read(apiProvider).search(query);
}
