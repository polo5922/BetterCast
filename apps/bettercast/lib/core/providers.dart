import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:bettercast_core/bettercast_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'connectivity.dart';
import 'local_db.dart';

/// Overridden in main() once the async singletons are ready.
final localDbProvider = Provider<LocalDb>((_) => throw UnimplementedError());
final tokenStoreProvider = Provider<TokenStore>((_) => throw UnimplementedError());

final apiProvider = Provider<ApiClient>((ref) {
  final api = ApiClient(ref.watch(tokenStoreProvider));
  api.onSessionExpired = () => ref.read(sessionProvider.notifier).expired();
  return api;
});

// ---- session -----------------------------------------------------------------

class Session {
  const Session({this.user, this.serverUrl});
  final UserProfile? user;
  final String? serverUrl;
  bool get signedIn => user != null;
}

class SessionNotifier extends Notifier<Session> {
  @override
  Session build() {
    final store = ref.read(tokenStoreProvider);
    final db = ref.read(localDbProvider);
    if (store.tokens == null) return Session(serverUrl: store.serverUrl);
    // Optimistic: restore the cached profile so the app works offline.
    final cached = db.getCache('me');
    final user = cached is Map ? UserProfile.fromJson(cached.cast()) : null;
    unawaited(Future.microtask(refreshProfile));
    return Session(
      user: user ?? const UserProfile(id: '', email: ''),
      serverUrl: store.serverUrl,
    );
  }

  Future<void> refreshProfile() async {
    try {
      final me = await ref.read(apiProvider).me();
      ref.read(localDbProvider).putCache('me', me.toJson());
      state = Session(user: me, serverUrl: state.serverUrl);
    } on ApiException catch (e) {
      if (e.status == 401) expired();
    }
  }

  Future<void> signIn(String server, String email, String password,
      {bool register = false, String? displayName}) async {
    final url = normalizeServerUrl(server);
    final res = await ref.read(apiProvider).login(url, email, password,
        register: register, displayName: displayName);
    ref.read(localDbProvider).putCache('me', res.user.toJson());
    state = Session(user: res.user, serverUrl: url);
  }

  Future<void> signOut() async {
    await ref.read(apiProvider).logout();
    state = Session(serverUrl: state.serverUrl);
  }

  void expired() => state = Session(serverUrl: state.serverUrl);
}

String normalizeServerUrl(String s) {
  var url = s.trim();
  if (!url.startsWith('http://') && !url.startsWith('https://')) url = 'https://$url';
  while (url.endsWith('/')) {
    url = url.substring(0, url.length - 1);
  }
  return url;
}

final sessionProvider = NotifierProvider<SessionNotifier, Session>(SessionNotifier.new);

// ---- episode states (position / played / liked), offline-first ---------------

class EpisodeStatesNotifier extends Notifier<Map<String, EpisodeState>> {
  Timer? _pushTimer;
  bool _syncing = false;

  @override
  Map<String, EpisodeState> build() {
    ref.onDispose(() => _pushTimer?.cancel());
    // Back online: push what was listened to offline right away.
    ref.listen<bool>(onlineProvider, (was, online) {
      if (online && was == false) unawaited(sync());
    });
    return ref.read(localDbProvider).allStates();
  }

  EpisodeState of(String episodeId, {String? podcastId}) =>
      state[episodeId] ??
      EpisodeState(
        episodeId: episodeId,
        podcastId: podcastId,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );

  void _put(EpisodeState s, {bool pushSoon = true}) {
    ref.read(localDbProvider).saveState(s, dirty: true);
    state = {...state, s.episodeId: s};
    if (pushSoon) _schedulePush();
  }

  void toggleLike(Episode e) {
    final cur = of(e.id, podcastId: e.podcastId);
    _put(EpisodeState(
      episodeId: e.id,
      podcastId: e.podcastId,
      position: cur.position,
      played: cur.played,
      liked: !cur.liked,
      updatedAt: DateTime.now().toUtc(),
    ));
  }

  void setPlayed(Episode e, bool played) {
    final cur = of(e.id, podcastId: e.podcastId);
    _put(EpisodeState(
      episodeId: e.id,
      podcastId: e.podcastId,
      position: played ? Duration.zero : cur.position,
      played: played,
      liked: cur.liked,
      updatedAt: DateTime.now().toUtc(),
    ));
  }

  /// Called by the player every few seconds; pushes are debounced.
  void savePosition(Episode e, Duration position, {Duration? duration}) {
    final cur = of(e.id, podcastId: e.podcastId);
    final total = duration ?? e.duration;
    final finished = total != null &&
        total > Duration.zero &&
        position >= total - const Duration(seconds: 20);
    _put(EpisodeState(
      episodeId: e.id,
      podcastId: e.podcastId,
      position: finished ? Duration.zero : position,
      played: finished || cur.played,
      liked: cur.liked,
      updatedAt: DateTime.now().toUtc(),
    ));
  }

  void _schedulePush() {
    _pushTimer?.cancel();
    _pushTimer = Timer(const Duration(seconds: 5), sync);
  }

  /// Pushes local changes, then pulls the server's.
  Future<void> sync() async {
    if (_syncing || !ref.read(sessionProvider).signedIn) return;
    _syncing = true;
    final db = ref.read(localDbProvider);
    final api = ref.read(apiProvider);
    try {
      final dirty = db.dirtyStates();
      if (dirty.isNotEmpty) {
        await api.pushStates(dirty);
        db.markClean(dirty);
      }
      final since = DateTime.tryParse(db.getKv('states_since') ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      final res = await api.pullStates(since);
      if (res.states.isNotEmpty) {
        final next = {...state};
        for (final s in res.states) {
          final local = next[s.episodeId];
          if (local == null || s.updatedAt.isAfter(local.updatedAt)) {
            db.saveState(s, dirty: false);
            next[s.episodeId] = s;
          }
        }
        state = next;
      }
      db.setKv('states_since', res.serverTime.toUtc().toIso8601String());
      ref.read(onlineProvider.notifier).reportOnline();
    } on ApiException catch (e) {
      // Offline: pushed again as soon as the server is reachable.
      if (e.isOffline) ref.read(onlineProvider.notifier).reportOffline();
    } finally {
      _syncing = false;
    }
  }
}

final episodeStatesProvider =
    NotifierProvider<EpisodeStatesNotifier, Map<String, EpisodeState>>(
        EpisodeStatesNotifier.new);

final episodeStateProvider = Provider.family<EpisodeState, String>((ref, id) {
  final s = ref.watch(episodeStatesProvider.select((m) => m[id]));
  return s ??
      EpisodeState(
          episodeId: id, updatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true));
});

// ---- remote data with an offline cache ---------------------------------------

/// Fetches [load], caches the JSON under [key], and falls back to the cache
/// when the server is unreachable.
Future<T> cached<T>(
  Ref ref,
  String key,
  Future<T> Function() load,
  Object Function(T) encode,
  T Function(dynamic) decode,
) async {
  final db = ref.read(localDbProvider);
  try {
    final v = await load();
    db.putCache(key, encode(v));
    ref.read(onlineProvider.notifier).reportOnline();
    return v;
  } on ApiException catch (e) {
    if (e.isOffline) ref.read(onlineProvider.notifier).reportOffline();
    final c = db.getCache(key);
    if (e.isOffline && c != null) return decode(c);
    rethrow;
  }
}

/// Refetches remote data when the server becomes reachable again.
void _refreshWhenOnline(Ref ref) => ref.listen<bool>(onlineProvider, (was, online) {
      if (online && was == false) ref.invalidateSelf();
    });

final subscriptionsProvider = FutureProvider<List<Subscription>>((ref) {
  ref.watch(sessionProvider.select((s) => s.user?.id));
  _refreshWhenOnline(ref);
  return cached(
    ref,
    'subscriptions',
    () => ref.read(apiProvider).subscriptions(),
    (v) => [for (final s in v) s.toJson()],
    (c) => [for (final s in c as List) Subscription.fromJson((s as Map).cast())],
  );
});

final subscribedIdsProvider = Provider<Set<String>>((ref) => {
      for (final s in ref.watch(subscriptionsProvider).value ?? const <Subscription>[])
        s.podcast.id,
    });

final newReleasesProvider = FutureProvider<List<FeedItem>>((ref) {
  ref.watch(sessionProvider.select((s) => s.user?.id));
  _refreshWhenOnline(ref);
  return cached(
    ref,
    'feed_new',
    () async {
      final v = await ref.read(apiProvider).newReleases(limit: 100);
      ref.read(localDbProvider).putEpisodes(v);
      return v;
    },
    (v) => [for (final i in v) i.toJson()],
    (c) => [for (final i in c as List) FeedItem.fromJson((i as Map).cast())],
  );
});

final podcastDetailProvider = FutureProvider.family<PodcastDetail, String>((ref, id) {
  return cached(
    ref,
    'podcast_$id',
    () async {
      final d = await ref.read(apiProvider).podcast(id);
      ref.read(localDbProvider)
          .putEpisodes([for (final e in d.episodes) FeedItem(episode: e, podcast: d.podcast)]);
      return d;
    },
    (v) => v.toJson(),
    (c) => PodcastDetail.fromJson((c as Map).cast()),
  );
});

/// Episodes for a list of ids (likes, in progress), cached locally.
final _episodesByIdsProvider =
    FutureProvider.family<List<FeedItem>, String>((ref, joinedIds) async {
  final ids = joinedIds.isEmpty ? <String>[] : joinedIds.split(',');
  _refreshWhenOnline(ref);
  final db = ref.read(localDbProvider);
  try {
    final v = await ref.read(apiProvider).episodesByIds(ids);
    db.putEpisodes(v);
    ref.read(onlineProvider.notifier).reportOnline();
    return v;
  } on ApiException catch (e) {
    if (!e.isOffline) rethrow;
    ref.read(onlineProvider.notifier).reportOffline();
    // Offline: rebuild the list from episodes seen before and downloads.
    final known = {for (final i in db.episodesByIds(ids)) i.episode.id: i};
    for (final d in db.downloads()) {
      known.putIfAbsent(d.item.episode.id, () => d.item);
    }
    return [for (final id in ids) ?known[id]];
  }
});

final likedEpisodesProvider = FutureProvider<List<FeedItem>>((ref) async {
  final states = ref.watch(episodeStatesProvider);
  final liked = states.values.where((s) => s.liked).toList()
    ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  return ref.watch(_episodesByIdsProvider(liked.map((s) => s.episodeId).join(',')).future);
});

final inProgressEpisodesProvider = FutureProvider<List<FeedItem>>((ref) async {
  final states = ref.watch(episodeStatesProvider);
  final ids = (states.values.where((s) => s.inProgress).toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt)))
      .take(50)
      .map((s) => s.episodeId)
      .join(',');
  return ref.watch(_episodesByIdsProvider(ids).future);
});

final searchQueryProvider = NotifierProvider<SearchQuery, String>(SearchQuery.new);

class SearchQuery extends Notifier<String> {
  @override
  String build() => '';
  void set(String q) => state = q;
}

final searchResultsProvider = FutureProvider<List<SearchResult>>((ref) async {
  final q = ref.watch(searchQueryProvider).trim();
  final api = ref.read(apiProvider);
  if (q.length < 2) return const [];
  // Debounce typing.
  var alive = true;
  ref.onDispose(() => alive = false);
  await Future<void>.delayed(const Duration(milliseconds: 350));
  if (!alive) throw StateError('cancelled');
  return api.search(q);
});

/// Top podcasts, overall (null) or for an Apple genre id.
final trendingProvider = FutureProvider.family<List<SearchResult>, String?>((ref, genre) {
  final cc = PlatformDispatcher.instance.locale.countryCode?.toLowerCase();
  return cached(
    ref,
    'trending_${genre ?? 'all'}',
    () => ref.read(apiProvider).trending(country: cc ?? 'fr', genre: genre),
    (v) => [for (final r in v) r.toJson()],
    (c) => [for (final r in c as List) SearchResult.fromJson((r as Map).cast())],
  );
});

final patreonCampaignsProvider = FutureProvider<List<PatreonCampaign>>((ref) =>
    ref.read(apiProvider).patreonCampaigns());
