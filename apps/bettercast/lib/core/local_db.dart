import 'dart:convert';
import 'dart:io';

import 'package:bettercast_core/bettercast_core.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

/// Local SQLite store: offline cache, playback states (with a dirty flag for
/// sync) and downloaded files.
class LocalDb {
  LocalDb._(this._db);

  final Database _db;

  static Future<LocalDb> open({String? path}) async {
    final file = path ??
        p.join((await getApplicationSupportDirectory()).path, 'bettercast.db');
    await Directory(p.dirname(file)).create(recursive: true);
    final db = LocalDb._(sqlite3.open(file));
    db._migrate();
    return db;
  }

  static LocalDb inMemory() => LocalDb._(sqlite3.openInMemory()).._migrate();

  void _migrate() {
    _db.execute('PRAGMA journal_mode=WAL');
    final version = _db.select('PRAGMA user_version').first.values.first as int;
    if (version < 1) {
      _db.execute('''
        CREATE TABLE cache (key TEXT PRIMARY KEY, json TEXT NOT NULL, updated_at INTEGER NOT NULL);
        CREATE TABLE episode_states (
          episode_id TEXT PRIMARY KEY, podcast_id TEXT, position_ms INTEGER NOT NULL,
          played INTEGER NOT NULL, liked INTEGER NOT NULL, updated_at TEXT NOT NULL,
          dirty INTEGER NOT NULL DEFAULT 0);
        CREATE TABLE downloads (
          episode_id TEXT PRIMARY KEY, item_json TEXT NOT NULL, variant_url TEXT NOT NULL,
          path TEXT, status TEXT NOT NULL, progress REAL NOT NULL DEFAULT 0,
          created_at INTEGER NOT NULL);
        CREATE TABLE kv (key TEXT PRIMARY KEY, value TEXT);
        PRAGMA user_version = 1;
      ''');
    }
  }

  void close() => _db.close();

  // ---- cache ----

  void putCache(String key, Object json) => _db.execute(
        'INSERT OR REPLACE INTO cache(key, json, updated_at) VALUES (?, ?, ?)',
        [key, jsonEncode(json), DateTime.now().millisecondsSinceEpoch],
      );

  dynamic getCache(String key) {
    final r = _db.select('SELECT json FROM cache WHERE key = ?', [key]);
    return r.isEmpty ? null : jsonDecode(r.first['json'] as String);
  }

  // ---- kv ----

  String? getKv(String key) {
    final r = _db.select('SELECT value FROM kv WHERE key = ?', [key]);
    return r.isEmpty ? null : r.first['value'] as String?;
  }

  Map<String, String> kvWithPrefix(String prefix) => {
        for (final r in _db.select(
            "SELECT key, value FROM kv WHERE substr(key, 1, ?) = ? AND value IS NOT NULL",
            [prefix.length, prefix]))
          r['key'] as String: r['value'] as String,
      };

  void setKv(String key, String? value) =>
      _db.execute('INSERT OR REPLACE INTO kv(key, value) VALUES (?, ?)', [key, value]);

  // ---- episode states ----

  Map<String, EpisodeState> allStates() => {
        for (final r in _db.select('SELECT * FROM episode_states'))
          r['episode_id'] as String: _stateFrom(r),
      };

  EpisodeState _stateFrom(Row r) => EpisodeState(
        episodeId: r['episode_id'] as String,
        podcastId: r['podcast_id'] as String?,
        position: Duration(milliseconds: r['position_ms'] as int),
        played: r['played'] == 1,
        liked: r['liked'] == 1,
        updatedAt: DateTime.parse(r['updated_at'] as String),
      );

  /// Saves [s]; [dirty] marks it for upload. Remote states only overwrite
  /// local ones when they are newer (last-write-wins).
  void saveState(EpisodeState s, {required bool dirty}) => _db.execute(
        'INSERT INTO episode_states(episode_id, podcast_id, position_ms, played, liked, updated_at, dirty) '
        'VALUES (?, ?, ?, ?, ?, ?, ?) ON CONFLICT(episode_id) DO UPDATE SET '
        'podcast_id = COALESCE(excluded.podcast_id, podcast_id), position_ms = excluded.position_ms, '
        'played = excluded.played, liked = excluded.liked, updated_at = excluded.updated_at, '
        'dirty = excluded.dirty WHERE excluded.updated_at >= updated_at',
        [
          s.episodeId,
          s.podcastId,
          s.position.inMilliseconds,
          s.played ? 1 : 0,
          s.liked ? 1 : 0,
          s.updatedAt.toUtc().toIso8601String(),
          dirty ? 1 : 0,
        ],
      );

  List<EpisodeState> dirtyStates() => [
        for (final r in _db.select('SELECT * FROM episode_states WHERE dirty = 1 LIMIT 500'))
          _stateFrom(r),
      ];

  /// Clears the dirty flag unless the row changed again since [s] was read.
  void markClean(Iterable<EpisodeState> states) {
    final stmt = _db.prepare(
        'UPDATE episode_states SET dirty = 0 WHERE episode_id = ? AND updated_at = ?');
    for (final s in states) {
      stmt.execute([s.episodeId, s.updatedAt.toUtc().toIso8601String()]);
    }
    stmt.close();
  }

  // ---- downloads ----

  List<DownloadRecord> downloads() => [
        for (final r in _db.select('SELECT * FROM downloads ORDER BY created_at DESC'))
          DownloadRecord(
            item: FeedItem.fromJson((jsonDecode(r['item_json'] as String) as Map).cast()),
            variantUrl: r['variant_url'] as String,
            path: r['path'] as String?,
            status: r['status'] as String,
            progress: (r['progress'] as num).toDouble(),
          ),
      ];

  void saveDownload(DownloadRecord d) => _db.execute(
        'INSERT INTO downloads(episode_id, item_json, variant_url, path, status, progress, created_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?) ON CONFLICT(episode_id) DO UPDATE SET '
        'variant_url = excluded.variant_url, path = excluded.path, status = excluded.status, '
        'progress = excluded.progress',
        [
          d.item.episode.id,
          jsonEncode(d.item.toJson()),
          d.variantUrl,
          d.path,
          d.status,
          d.progress,
          DateTime.now().millisecondsSinceEpoch,
        ],
      );

  void deleteDownload(String episodeId) =>
      _db.execute('DELETE FROM downloads WHERE episode_id = ?', [episodeId]);
}

class DownloadRecord {
  const DownloadRecord({
    required this.item,
    required this.variantUrl,
    this.path,
    required this.status,
    this.progress = 0,
  });

  final FeedItem item;
  final String variantUrl;
  final String? path;

  /// queued | running | complete | failed
  final String status;
  final double progress;

  bool get isComplete => status == 'complete' && path != null;

  DownloadRecord copyWith({String? path, String? status, double? progress}) =>
      DownloadRecord(
        item: item,
        variantUrl: variantUrl,
        path: path ?? this.path,
        status: status ?? this.status,
        progress: progress ?? this.progress,
      );
}
