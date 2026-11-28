import 'dart:async';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:bettercast_core/bettercast_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'artwork_cache.dart';
import 'local_db.dart';
import 'providers.dart';

/// Offline episodes. Downloads the audio variant by default (smaller), or
/// the variant explicitly requested.
class DownloadsNotifier extends Notifier<Map<String, DownloadRecord>> {
  final _tasks = <String, String>{}; // episodeId -> taskId

  LocalDb get _db => ref.read(localDbProvider);

  @override
  Map<String, DownloadRecord> build() {
    final all = {for (final d in _db.downloads()) d.item.episode.id: d};
    // Interrupted downloads (app killed) are marked failed for a retry.
    for (final d in all.values.where((d) => !d.isComplete)) {
      all[d.item.episode.id] = d.copyWith(status: 'failed');
      _db.saveDownload(all[d.item.episode.id]!);
    }
    return all;
  }

  DownloadRecord? of(String episodeId) => state[episodeId];

  /// Local file for [variantUrl] if it has been downloaded.
  String? localPath(String episodeId, String variantUrl) {
    final d = state[episodeId];
    if (d == null || !d.isComplete || d.variantUrl != variantUrl) return null;
    return File(d.path!).existsSync() ? d.path : null;
  }

  void _set(DownloadRecord d) {
    _db.saveDownload(d);
    state = {...state, d.item.episode.id: d};
  }

  Future<void> download(FeedItem item, {MediaVariant? variant, bool wifiOnly = false}) async {
    final v = variant ?? item.episode.audio ?? item.episode.defaultVariant;
    if (v == null) return;
    final ext = _extension(v);
    final task = DownloadTask(
      url: v.url,
      filename: '${item.episode.id}$ext',
      directory: 'episodes',
      baseDirectory: BaseDirectory.applicationSupport,
      updates: Updates.statusAndProgress,
      retries: 3,
      requiresWiFi: wifiOnly,
      allowPause: true,
      displayName: item.episode.title,
    );
    _tasks[item.episode.id] = task.taskId;
    // Covers too, so the episode looks the same offline.
    unawaited(ArtworkCache.save(item.episode.imageUrl));
    unawaited(ArtworkCache.save(item.podcast.imageUrl));
    var rec = DownloadRecord(item: item, variantUrl: v.url, status: 'running');
    _set(rec);
    final result = await FileDownloader().download(
      task,
      onProgress: (p) {
        if (p >= 0) {
          rec = rec.copyWith(progress: p);
          state = {...state, item.episode.id: rec};
        }
      },
    );
    _tasks.remove(item.episode.id);
    if (result.status == TaskStatus.complete) {
      _set(rec.copyWith(status: 'complete', progress: 1, path: await task.filePath()));
    } else if (result.status == TaskStatus.canceled) {
      _db.deleteDownload(item.episode.id);
      state = {...state}..remove(item.episode.id);
    } else {
      _set(rec.copyWith(status: 'failed'));
    }
  }

  Future<void> remove(String episodeId) async {
    final taskId = _tasks.remove(episodeId);
    if (taskId != null) await FileDownloader().cancelTaskWithId(taskId);
    final d = state[episodeId];
    if (d?.path != null) {
      try {
        await File(d!.path!).delete();
      } catch (_) {}
    }
    _db.deleteDownload(episodeId);
    state = {...state}..remove(episodeId);
    if (d != null) await _dropArtwork(d.item);
  }

  /// Deletes covers no other download still uses.
  Future<void> _dropArtwork(FeedItem item) async {
    final used = {
      for (final o in state.values) ...[o.item.episode.imageUrl, o.item.podcast.imageUrl],
    };
    for (final url in {item.episode.imageUrl, item.podcast.imageUrl}) {
      if (url != null && !used.contains(url)) await ArtworkCache.remove(url);
    }
  }

  static String _extension(MediaVariant v) {
    final path = Uri.tryParse(v.url)?.path ?? '';
    final dot = path.lastIndexOf('.');
    if (dot > path.lastIndexOf('/') && path.length - dot <= 5) return path.substring(dot);
    return switch (v.mimeType) {
      'audio/mpeg' => '.mp3',
      'audio/mp4' || 'audio/x-m4a' || 'audio/aac' => '.m4a',
      'audio/ogg' || 'audio/opus' => '.ogg',
      'video/mp4' => '.mp4',
      'video/webm' => '.webm',
      _ => v.kind == MediaKind.video ? '.mp4' : '.mp3',
    };
  }
}

final downloadsProvider =
    NotifierProvider<DownloadsNotifier, Map<String, DownloadRecord>>(DownloadsNotifier.new);
