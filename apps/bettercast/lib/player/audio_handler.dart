import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:bettercast_core/bettercast_core.dart';

import 'player_controller.dart';

/// Content shown in Android Auto's browse tree.
abstract class MediaLibrary {
  Future<List<FeedItem>> newReleases();
  Future<List<FeedItem>> inProgress();
  Future<List<FeedItem>> liked();
  Future<List<FeedItem>> downloaded();
  Future<List<Podcast>> subscriptions();
  Future<List<FeedItem>> podcastEpisodes(String podcastId);
  Future<List<SearchResult>> search(String query);
}

/// Bridges [PlayerController] to Android's MediaSession / MediaBrowserService
/// (notification, lock screen, Bluetooth buttons and Android Auto).
class BetterCastAudioHandler extends BaseAudioHandler with QueueHandler {
  BetterCastAudioHandler(this.controller, this.library) {
    controller.addListener(_sync);
    _posSub = controller.positionStream.listen((_) => _throttledSync());
    _sync();
  }

  final PlayerController controller;
  final MediaLibrary library;
  late final StreamSubscription<Duration> _posSub;
  DateTime _lastSync = DateTime(0);
  final _known = <String, FeedItem>{};

  static const _new = 'new';
  static const _progress = 'progress';
  static const _subs = 'subs';
  static const _liked = 'liked';
  static const _downloads = 'downloads';
  static const _podcastPrefix = 'podcast:';
  static const _episodePrefix = 'episode:';

  // ---- state -> MediaSession ----

  void _throttledSync() {
    final now = DateTime.now();
    if (now.difference(_lastSync) > const Duration(seconds: 1)) _sync();
  }

  void _sync() {
    _lastSync = DateTime.now();
    final item = controller.current;
    if (item != null) {
      final m = _toMediaItem(item, duration: controller.duration);
      if (mediaItem.value != m) mediaItem.add(m);
    }
    queue.add([for (final q in controller.queue) _toMediaItem(q)]);
    playbackState.add(PlaybackState(
      controls: [
        MediaControl.rewind,
        if (controller.playing) MediaControl.pause else MediaControl.play,
        MediaControl.fastForward,
        if (controller.queue.isNotEmpty) MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
        MediaAction.playPause,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: item == null
          ? AudioProcessingState.idle
          : controller.buffering
              ? AudioProcessingState.buffering
              : AudioProcessingState.ready,
      playing: controller.playing,
      updatePosition: controller.position,
      speed: controller.rate,
      queueIndex: item == null ? null : 0,
    ));
  }

  MediaItem _toMediaItem(FeedItem item, {Duration? duration}) {
    _known[item.episode.id] = item;
    final art = item.episode.imageUrl ?? item.podcast.imageUrl;
    return MediaItem(
      id: '$_episodePrefix${item.episode.id}',
      title: item.episode.title,
      album: item.podcast.title,
      artist: item.podcast.author ?? item.podcast.title,
      duration: duration ?? item.episode.duration,
      artUri: art == null ? null : Uri.tryParse(art),
      playable: true,
      extras: {'podcastId': item.podcast.id},
    );
  }

  MediaItem _folder(String id, String title, {String? art}) => MediaItem(
        id: id,
        title: title,
        playable: false,
        artUri: art == null ? null : Uri.tryParse(art),
      );

  // ---- transport controls ----

  @override
  Future<void> play() => controller.resume();
  @override
  Future<void> pause() => controller.pause();
  @override
  Future<void> stop() async {
    await controller.stop();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) => controller.seek(position);
  @override
  Future<void> fastForward() => controller.skip(const Duration(seconds: 30));
  @override
  Future<void> rewind() => controller.skip(const Duration(seconds: -15));
  @override
  Future<void> skipToNext() => controller.skipToNext();
  @override
  Future<void> setSpeed(double speed) => controller.setRate(speed);

  @override
  Future<void> onTaskRemoved() => controller.pause();

  // ---- Android Auto browse tree ----

  @override
  Future<List<MediaItem>> getChildren(String parentMediaId,
      [Map<String, dynamic>? options]) async {
    // Car screens never show video: make sure we decode audio only.
    unawaited(controller.setBackgroundMode(true));
    switch (parentMediaId) {
      case AudioService.browsableRootId:
        return [
          _folder(_new, 'Nouveautés'),
          _folder(_progress, 'En cours'),
          _folder(_subs, 'Abonnements'),
          _folder(_liked, 'Likés'),
          _folder(_downloads, 'Téléchargés'),
        ];
      case AudioService.recentRootId:
        final items = await library.inProgress();
        return [for (final i in items.take(10)) _toMediaItem(i)];
      case _new:
        return [for (final i in (await library.newReleases()).take(50)) _toMediaItem(i)];
      case _progress:
        return [for (final i in await library.inProgress()) _toMediaItem(i)];
      case _liked:
        return [for (final i in await library.liked()) _toMediaItem(i)];
      case _downloads:
        return [for (final i in await library.downloaded()) _toMediaItem(i)];
      case _subs:
        return [
          for (final p in await library.subscriptions())
            _folder('$_podcastPrefix${p.id}', p.title, art: p.imageUrl),
        ];
    }
    if (parentMediaId.startsWith(_podcastPrefix)) {
      final items = await library.podcastEpisodes(parentMediaId.substring(_podcastPrefix.length));
      return [for (final i in items.take(100)) _toMediaItem(i)];
    }
    return const [];
  }

  @override
  Future<MediaItem?> getMediaItem(String mediaId) async {
    final item = _known[mediaId.replaceFirst(_episodePrefix, '')];
    return item == null ? null : _toMediaItem(item);
  }

  @override
  Future<void> playFromMediaId(String mediaId, [Map<String, dynamic>? extras]) async {
    final item = _known[mediaId.replaceFirst(_episodePrefix, '')];
    if (item != null) await controller.play(item, kind: _audioFirst(item));
  }

  MediaKind? _audioFirst(FeedItem item) => item.episode.hasAudio ? MediaKind.audio : null;

  @override
  Future<List<MediaItem>> search(String query, [Map<String, dynamic>? extras]) async {
    final results = await library.search(query);
    return [
      for (final r in results.take(20))
        _folder('$_podcastPrefix${r.podcastId}', r.title, art: r.imageUrl),
    ];
  }

  /// "Ok Google, play `podcast` on BetterCast".
  @override
  Future<void> playFromSearch(String query, [Map<String, dynamic>? extras]) async {
    var items = <FeedItem>[];
    if (query.trim().isEmpty) {
      items = [...await library.inProgress()];
      if (items.isEmpty) items = [...await library.newReleases()];
    } else {
      final subs = await library.subscriptions();
      final q = query.toLowerCase();
      final match = subs.where((p) => p.title.toLowerCase().contains(q)).firstOrNull;
      items = match == null ? [] : await library.podcastEpisodes(match.id);
    }
    if (items.isNotEmpty) {
      _toMediaItem(items.first);
      await controller.play(items.first, kind: _audioFirst(items.first));
    }
  }

  Future<void> dispose() async {
    controller.removeListener(_sync);
    await _posSub.cancel();
  }
}
