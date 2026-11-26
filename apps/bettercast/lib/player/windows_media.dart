import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:smtc_windows/smtc_windows.dart';

import 'player_controller.dart';

/// Windows System Media Transport Controls (media keys, volume flyout,
/// lock screen).
class WindowsMediaControls {
  WindowsMediaControls(this.controller);

  final PlayerController controller;
  SMTCWindows? _smtc;
  StreamSubscription<PressedButton>? _buttons;
  String? _lastEpisode;
  bool? _lastPlaying;
  DateTime _lastTimeline = DateTime(0);

  static Future<void> initialize() => SMTCWindows.initialize();

  void start() {
    try {
      _smtc = SMTCWindows(
        config: const SMTCConfig(
          playEnabled: true,
          pauseEnabled: true,
          stopEnabled: true,
          nextEnabled: true,
          prevEnabled: false,
          fastForwardEnabled: true,
          rewindEnabled: true,
        ),
      );
      _buttons = _smtc!.buttonPressStream.listen(_onButton);
      controller.addListener(_sync);
    } catch (e) {
      debugPrint('SMTC unavailable: $e');
    }
  }

  void _onButton(PressedButton b) {
    switch (b) {
      case PressedButton.play:
        controller.resume();
      case PressedButton.pause:
        controller.pause();
      case PressedButton.next:
        controller.skipToNext();
      case PressedButton.fastForward:
        controller.skip(const Duration(seconds: 30));
      case PressedButton.rewind || PressedButton.previous:
        controller.skip(const Duration(seconds: -15));
      case PressedButton.stop:
        controller.stop();
      default:
        break;
    }
  }

  Future<void> _sync() async {
    final smtc = _smtc;
    if (smtc == null) return;
    final item = controller.current;
    try {
      if (item == null) {
        if (_lastEpisode != null) {
          _lastEpisode = null;
          await smtc.clearMetadata();
          await smtc.setPlaybackStatus(PlaybackStatus.stopped);
        }
        return;
      }
      if (_lastEpisode != item.episode.id) {
        _lastEpisode = item.episode.id;
        await smtc.enableSmtc();
        await smtc.updateMetadata(MusicMetadata(
          title: item.episode.title,
          artist: item.podcast.author ?? item.podcast.title,
          album: item.podcast.title,
          albumArtist: item.podcast.title,
          thumbnail: item.episode.imageUrl ?? item.podcast.imageUrl,
        ));
      }
      if (_lastPlaying != controller.playing) {
        _lastPlaying = controller.playing;
        await smtc.setPlaybackStatus(
            controller.playing ? PlaybackStatus.playing : PlaybackStatus.paused);
      }
      final now = DateTime.now();
      final total = controller.duration;
      if (total != null && now.difference(_lastTimeline) > const Duration(seconds: 5)) {
        _lastTimeline = now;
        await smtc.updateTimeline(PlaybackTimeline(
          startTimeMs: 0,
          endTimeMs: total.inMilliseconds,
          positionMs: controller.position.inMilliseconds,
          minSeekTimeMs: 0,
          maxSeekTimeMs: total.inMilliseconds,
        ));
      }
    } catch (e) {
      debugPrint('SMTC update failed: $e');
    }
  }

  Future<void> dispose() async {
    controller.removeListener(_sync);
    await _buttons?.cancel();
    await _smtc?.dispose();
  }
}
