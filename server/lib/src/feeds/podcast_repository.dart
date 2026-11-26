import 'dart:convert';

import 'package:bettercast_core/bettercast_core.dart';
import 'package:postgres/postgres.dart';

import '../http/json.dart';
import '../security/crypto.dart';
import 'feed_fetcher.dart';

/// A podcast row as needed by the refresh worker.
class PodcastRow {
  const PodcastRow({
    required this.id,
    required this.source,
    this.feedUrl,
    this.privateFeedEnc,
    this.etag,
    this.lastModified,
    this.lastFetchedAt,
    this.failCount = 0,
  });

  final String id;
  final PodcastSource source;
  final String? feedUrl;
  final String? privateFeedEnc;
  final String? etag;
  final String? lastModified;
  final DateTime? lastFetchedAt;
  final int failCount;

  bool get isPrivate => feedUrl == null;
}

class RefreshResult {
  const RefreshResult(this.podcast, this.newEpisodes);
  final Podcast? podcast;

  /// Episodes inserted by this refresh (empty on the very first fetch).
  final List<Episode> newEpisodes;
}

class PodcastRepository {
  PodcastRepository(this._db, this._fetcher, this._crypto);

  final Pool _db;
  final FeedFetcher _fetcher;
  final Encryptor _crypto;
  final _parser = const FeedParser();

  static const _cols = 'id, source, feed_url, private_feed_enc, etag, '
      'last_modified, last_fetched_at, fail_count';

  PodcastRow _row(ResultRow r) => PodcastRow(
        id: r[0] as String,
        source: PodcastSource.values.asNameMap()[r[1]] ?? PodcastSource.rss,
        feedUrl: r[2] as String?,
        privateFeedEnc: r[3] as String?,
        etag: r[4] as String?,
        lastModified: r[5] as String?,
        lastFetchedAt: r[6] as DateTime?,
        failCount: r[7] as int,
      );

  // ---- reads -------------------------------------------------------------

  /// Throws 404 if the podcast does not exist or is private to someone else.
  Future<Podcast> get(String id, {required String userId}) async {
    final rows = await _db.execute(
      Sql.named('SELECT data FROM podcasts WHERE id = @id '
          'AND (owner_user_id IS NULL OR owner_user_id = @u::uuid)'),
      parameters: {'id': id, 'u': userId},
    );
    if (rows.isEmpty) throw ApiException.notFound('Podcast not found');
    return Podcast.fromJson((rows.first[0] as Map).cast());
  }

  Future<List<Episode>> episodes(
    String podcastId, {
    int limit = 50,
    int offset = 0,
  }) async {
    final rows = await _db.execute(
      Sql.named('SELECT data FROM episodes WHERE podcast_id = @p '
          'ORDER BY published_at DESC NULLS LAST LIMIT @l OFFSET @o'),
      parameters: {'p': podcastId, 'l': limit.clamp(1, 500), 'o': offset},
    );
    return [for (final r in rows) Episode.fromJson((r[0] as Map).cast())];
  }

  Future<List<FeedItem>> episodesByIds(List<String> ids) async {
    if (ids.isEmpty) return [];
    final rows = await _db.execute(
      Sql.named('SELECT e.data, p.data FROM episodes e '
          'JOIN podcasts p ON p.id = e.podcast_id WHERE e.id = ANY(@ids)'),
      parameters: {'ids': TypedValue(Type.textArray, ids)},
    );
    return [
      for (final r in rows)
        FeedItem(
          episode: Episode.fromJson((r[0] as Map).cast()),
          podcast: Podcast.fromJson((r[1] as Map).cast()),
        ),
    ];
  }

  Future<PodcastRow?> row(String id) async {
    final rows = await _db.execute(
      Sql.named('SELECT $_cols FROM podcasts WHERE id = @id'),
      parameters: {'id': id},
    );
    return rows.isEmpty ? null : _row(rows.first);
  }

  /// Podcasts due for refresh that at least one user follows.
  Future<List<PodcastRow>> due({int limit = 20}) async {
    final rows = await _db.execute(
      Sql.named('SELECT $_cols FROM podcasts p WHERE next_fetch_at <= now() '
          'AND EXISTS (SELECT 1 FROM subscriptions s WHERE s.podcast_id = p.id) '
          'ORDER BY next_fetch_at LIMIT @l'),
      parameters: {'l': limit},
    );
    return rows.map(_row).toList();
  }

  // ---- writes ------------------------------------------------------------

  /// Returns the public podcast for [feedUrl], fetching it on first use.
  Future<Podcast> ensurePublic(String feedUrl) async {
    final url = Podcast.normalizeFeedUrl(feedUrl);
    final id = Podcast.idFor(url);
    final existing = await _db.execute(
      Sql.named('SELECT data, last_fetched_at FROM podcasts WHERE id = @id'),
      parameters: {'id': id},
    );
    if (existing.isNotEmpty && existing.first[1] != null) {
      return Podcast.fromJson((existing.first[0] as Map).cast());
    }
    await _db.execute(
      Sql.named('INSERT INTO podcasts(id, feed_url) VALUES (@id, @url) '
          'ON CONFLICT (id) DO NOTHING'),
      parameters: {'id': id, 'url': url},
    );
    final result = await refresh((await row(id))!, rethrowErrors: true);
    return result.podcast!;
  }

  /// Creates (or updates the URL of) a private podcast owned by [userId].
  Future<Podcast> upsertPrivate({
    required String userId,
    required String feedUrl,
    required PodcastSource source,
    String? existingId,
  }) async {
    // Validate before storing anything.
    final res = await _fetcher.fetch(feedUrl);
    _parser.parse(res.body!, feedUrl: feedUrl, podcastId: 'probe');

    final id = existingId ?? 'pr_${randomToken(12)}';
    final enc = await _crypto.encrypt(feedUrl);
    await _db.execute(
      Sql.named('INSERT INTO podcasts(id, private_feed_enc, owner_user_id, source) '
          'VALUES (@id, @enc, @u::uuid, @s) ON CONFLICT (id) DO UPDATE SET '
          'private_feed_enc = EXCLUDED.private_feed_enc, etag = NULL, '
          'last_modified = NULL, next_fetch_at = now(), fail_count = 0'),
      parameters: {'id': id, 'enc': enc, 'u': userId, 's': source.name},
    );
    final result = await refresh((await row(id))!, rethrowErrors: true);
    return result.podcast!;
  }

  /// Fetches, parses and stores a feed. Never throws unless [rethrowErrors]:
  /// failures are recorded with exponential backoff.
  Future<RefreshResult> refresh(
    PodcastRow row, {
    bool rethrowErrors = false,
    Duration interval = const Duration(minutes: 20),
  }) async {
    try {
      final url = row.feedUrl ?? await _crypto.decrypt(row.privateFeedEnc!);
      final res = await _fetcher.fetch(
        url,
        etag: row.etag,
        lastModified: row.lastModified,
      );
      final next = row.isPrivate ? interval * 1.5 : interval;
      if (res.notModified) {
        await _db.execute(
          Sql.named('UPDATE podcasts SET last_fetched_at = now(), fail_count = 0, '
              'last_error = NULL, next_fetch_at = now() + @n::interval WHERE id = @id'),
          parameters: {'id': row.id, 'n': '${next.inSeconds} seconds'},
        );
        return const RefreshResult(null, []);
      }

      final parsed = _parser.parse(
        res.body!,
        feedUrl: url,
        podcastId: row.id,
        source: row.source,
        premium: row.isPrivate,
      );
      // Never leak the secret URL of private feeds to clients.
      final podcast = parsed.podcast.copyWith(
        feedUrl: row.isPrivate ? '' : parsed.podcast.feedUrl,
      );

      final inserted = await _db.runTx((tx) async {
        await tx.execute(
          Sql.named('UPDATE podcasts SET title = @t, data = @d::jsonb, etag = @e, '
              'last_modified = @lm, last_fetched_at = now(), fail_count = 0, '
              'last_error = NULL, next_fetch_at = now() + @n::interval WHERE id = @id'),
          parameters: {
            'id': row.id,
            't': podcast.title,
            'd': jsonEncode(podcast.toJson()),
            'e': res.etag,
            'lm': res.lastModified,
            'n': '${next.inSeconds} seconds',
          },
        );
        if (parsed.episodes.isEmpty) return <String>{};
        final payload = jsonEncode([
          for (final e in parsed.episodes)
            {
              'id': e.id,
              'guid': e.guid,
              'pub': dateToJson(e.publishedAt),
              'data': e.toJson(),
            },
        ]);
        final rows = await tx.execute(
          Sql.named('INSERT INTO episodes(id, podcast_id, guid, published_at, data) '
              'SELECT x.id, @p, x.guid, x.pub, x.data '
              'FROM jsonb_to_recordset(@rows::jsonb) '
              'AS x(id text, guid text, pub timestamptz, data jsonb) '
              'ON CONFLICT (id) DO UPDATE SET data = EXCLUDED.data, '
              'published_at = EXCLUDED.published_at, updated_at = now() '
              'WHERE episodes.data IS DISTINCT FROM EXCLUDED.data '
              'RETURNING id, (xmax = 0) AS inserted'),
          parameters: {'p': row.id, 'rows': payload},
        );
        return {for (final r in rows) if (r[1] == true) r[0] as String};
      });

      // The first fetch imports the back catalogue: nothing is "new".
      final isFirstFetch = row.lastFetchedAt == null;
      final cutoff = DateTime.now().toUtc().subtract(const Duration(days: 3));
      final fresh = isFirstFetch
          ? <Episode>[]
          : parsed.episodes
              .where((e) =>
                  inserted.contains(e.id) &&
                  (e.publishedAt == null || e.publishedAt!.isAfter(cutoff)))
              .toList();
      return RefreshResult(podcast, fresh);
    } catch (e) {
      final backoff = Duration(
        minutes: (20 * (1 << row.failCount.clamp(0, 6))).clamp(20, 24 * 60),
      );
      await _db.execute(
        Sql.named('UPDATE podcasts SET fail_count = fail_count + 1, '
            'last_error = @err, next_fetch_at = now() + @n::interval WHERE id = @id'),
        parameters: {
          'id': row.id,
          'err': e.toString(),
          'n': '${backoff.inSeconds} seconds',
        },
      );
      if (rethrowErrors) {
        if (e is ApiException) rethrow;
        throw ApiException(422, 'feed_unavailable', 'Could not read feed: $e');
      }
      return const RefreshResult(null, []);
    }
  }
}
