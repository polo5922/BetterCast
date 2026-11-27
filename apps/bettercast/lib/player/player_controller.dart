import 'dart:async';

import 'package:bettercast_core/bettercast_core.dart';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// Persistence hooks so the controller stays independent from Riverpod
/// (it is shared with the Android media service).
abstract class PlaybackStore {
  Duration resumePosition(Episode e);
  void savePosition(Episode e, Duration position, Duration? duration);
  void markPlayed(Episode e);
  String? localPath(Episode e, MediaVariant v);
}

/// Single source of truth for playback: current episode, queue, selected
/// media variant, speed and sleep timer.
class PlayerController extends ChangeNotifier {
  PlayerController(this._store) {
    _subs.addAll([
      player.stream.playing.listen((_) => notifyListeners()),
      player.stream.buffering.listen((_) => notifyListeners()),
      player.stream.duration.listen((d) {
        if (d > Duration.zero) _duration = d;
        notifyListeners();
      }),
      player.stream.completed.listen((done) {
        if (done && !_switching) unawaited(_onCompleted());
      }),
      player.stream.error.listen((e) => debugPrint('player: $e')),
    ]);
    _saveTimer = Timer.periodic(const Duration(seconds: 10), (_) => _persist());
  }

  final PlaybackStore _store;
  final Player player = Player(
    configuration: const PlayerConfiguration(title: 'BetterCast'),
  );
  final _subs = <StreamSubscription<Object?>>[];
  late final Timer _saveTimer;

  VideoController? _video;

  /// Created lazily: only needed once a video variant is shown.
  VideoController get videoController => _video ??= VideoController(player);

  FeedItem? _current;
  MediaVariant? _variant;
  Duration? _duration;
  final List<FeedItem> queue = [];
  double _rate = 1.0;
  bool _switching = false;
  bool _backgroundAudioOnly = false;
  bool _loading = false;

  /// Called before playback starts (Android: takes audio focus so the
  /// system, Bluetooth and Android Auto route audio to this app).
  /// Returning false cancels playback.
  Future<bool> Function()? onBeforePlay;
  Timer? _sleepTimer;
  DateTime? _sleepAt;
  bool _sleepAtEndOfEpisode = false;

  FeedItem? get current => _current;
  MediaVariant? get variant => _variant;
  bool get isVideo => _variant?.kind == MediaKind.video;
  bool get playing => player.state.playing;
  bool get buffering => player.state.buffering;

  /// True while a new stream is being opened.
  bool get loading => _loading;
  Duration get position => player.state.position;
  Duration? get duration => _duration ?? _current?.episode.duration;
  double get rate => _rate;
  DateTime? get sleepAt => _sleepAt;
  bool get sleepAtEndOfEpisode => _sleepAtEndOfEpisode;
  Stream<Duration> get positionStream => player.stream.position;

  /// Starts [item]. Resumes from the saved position unless [start] is given.
  Future<void> play(FeedItem item, {MediaKind? kind, Duration? start, bool autoplay = true}) async {
    if (_current?.episode.id == item.episode.id && kind == null && start == null) {
      if (!playing) await resume();
      return;
    }
    if (autoplay && !await _requestFocus()) return;
    _persist();
    final e = item.episode;
    final v = _pick(e, kind ?? _preferredKind(e));
    if (v == null) return;
    _current = item;
    _variant = v;
    _duration = e.duration;
    queue.removeWhere((q) => q.episode.id == e.id);
    notifyListeners();
    await _open(v, start ?? _store.resumePosition(e), autoplay: autoplay);
  }

  MediaKind _preferredKind(Episode e) {
    // Keep the kind the user last picked when possible; audio by default.
    if (_backgroundAudioOnly) return MediaKind.audio;
    final last = _variant?.kind;
    if (last == MediaKind.video && e.hasVideo) return MediaKind.video;
    return e.hasAudio ? MediaKind.audio : MediaKind.video;
  }

  MediaVariant? _pick(Episode e, MediaKind kind) =>
      (kind == MediaKind.video ? e.video : e.audio) ?? e.defaultVariant;

  Future<void> _open(MediaVariant v, Duration start, {bool autoplay = true}) async {
    final local = _store.localPath(_current!.episode, v);
    _switching = true;
    _loading = true;
    notifyListeners();
    try {
      await player.open(
        Media(local ?? v.url, start: start > Duration.zero ? start : null),
        play: autoplay,
      );
      await player.setRate(_rate);
    } finally {
      _switching = false;
      _loading = false;
      notifyListeners();
    }
  }

  /// Audio <-> video switch at the same position, without losing play state.
  Future<void> switchTo(MediaKind kind) async {
    final item = _current;
    if (item == null || _variant?.kind == kind) return;
    final next = kind == MediaKind.video ? item.episode.video : item.episode.audio;
    if (next == null) return;
    final pos = player.state.position;
    final wasPlaying = player.state.playing;
    _variant = next;
    notifyListeners();
    await _open(next, pos, autoplay: wasPlaying);
  }

  Future<void> toggleMediaKind() =>
      switchTo(isVideo ? MediaKind.audio : MediaKind.video);

  /// When the UI goes away (background, Android Auto) there is no point
  /// decoding video: fall back to audio if the episode has it.
  Future<void> setBackgroundMode(bool background) async {
    _backgroundAudioOnly = background;
    if (background && isVideo && (_current?.episode.hasAudio ?? false)) {
      await switchTo(MediaKind.audio);
    }
  }

  Future<void> playPause() => playing ? pause() : resume();
  Future<void> resume() async {
    if (_current == null || !await _requestFocus()) return;
    await player.play();
  }

  Future<void> pause() async {
    await player.pause();
    _persist();
  }

  Future<void> seek(Duration d) async {
    final total = duration;
    var target = d < Duration.zero ? Duration.zero : d;
    if (total != null && target > total) target = total;
    await player.seek(target);
    notifyListeners();
  }

  Future<void> skip(Duration delta) => seek(position + delta);

  Future<void> setRate(double r) async {
    _rate = r;
    await player.setRate(r);
    notifyListeners();
  }

  void enqueue(FeedItem item, {bool next = false}) {
    if (item.episode.id == _current?.episode.id) return;
    queue.removeWhere((q) => q.episode.id == item.episode.id);
    next ? queue.insert(0, item) : queue.add(item);
    notifyListeners();
  }

  void removeFromQueue(String episodeId) {
    queue.removeWhere((q) => q.episode.id == episodeId);
    notifyListeners();
  }

  Future<void> skipToNext() async {
    if (queue.isEmpty) return;
    await play(queue.removeAt(0));
  }

  Future<void> stop() async {
    _persist();
    await player.stop();
    _current = null;
    _variant = null;
    notifyListeners();
  }

  // ---- sleep timer ----

  void setSleepTimer(Duration? d, {bool endOfEpisode = false}) {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepAt = null;
    _sleepAtEndOfEpisode = endOfEpisode;
    if (d != null) {
      _sleepAt = DateTime.now().add(d);
      _sleepTimer = Timer(d, () {
        _sleepAt = null;
        unawaited(pause());
      });
    }
    notifyListeners();
  }

  Future<void> _onCompleted() async {
    final item = _current;
    if (item == null) return;
    _store.markPlayed(item.episode);
    if (_sleepAtEndOfEpisode) {
      _sleepAtEndOfEpisode = false;
      notifyListeners();
      return;
    }
    if (queue.isNotEmpty) {
      await play(queue.removeAt(0));
    } else {
      notifyListeners();
    }
  }

  Future<bool> _requestFocus() async {
    final hook = onBeforePlay;
    if (hook == null) return true;
    try {
      return await hook();
    } catch (e) {
      debugPrint('audio focus: $e');
      return true;
    }
  }

  void _persist() {
    final item = _current;
    if (item == null || _switching) return;
    final pos = player.state.position;
    if (pos > Duration.zero) _store.savePosition(item.episode, pos, duration);
  }

  @override
  void dispose() {
    _persist();
    _saveTimer.cancel();
    _sleepTimer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    player.dispose();
    super.dispose();
  }
}
