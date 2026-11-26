import 'package:bettercast_core/bettercast_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../ui/widgets.dart';
import 'themes.dart';

class DiscoverPage extends ConsumerStatefulWidget {
  const DiscoverPage({super.key});

  @override
  ConsumerState<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends ConsumerState<DiscoverPage> {
  late final _query = TextEditingController(text: ref.read(searchQueryProvider));
  bool _looking = false;

  bool get _isUrl {
    final t = _query.text.trim();
    return t.startsWith('http://') ||
        t.startsWith('https://') ||
        t.startsWith('feed://') ||
        t.startsWith('itpc://');
  }

  /// A pasted feed URL is looked up directly instead of searched.
  Future<void> _lookupUrl() async {
    setState(() => _looking = true);
    try {
      final d = await ref.read(apiProvider).lookup(_query.text.trim());
      if (mounted) context.push('/podcast/${d.podcast.id}');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _looking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(searchResultsProvider);
    final searching = ref.watch(searchQueryProvider).trim().length >= 2;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Découvrir'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: SearchBar(
              controller: _query,
              hintText: 'Rechercher un podcast ou coller l’URL d’un flux RSS',
              leading: const Icon(Icons.search),
              trailing: [
                if (_looking)
                  const SizedBox(
                      width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                else if (_query.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _query.clear();
                      ref.read(searchQueryProvider.notifier).set('');
                      setState(() {});
                    },
                  ),
              ],
              onChanged: (q) {
                setState(() {});
                if (!_isUrl) ref.read(searchQueryProvider.notifier).set(q);
              },
              onSubmitted: (_) => _isUrl ? _lookupUrl() : null,
            ),
          ),
        ),
      ),
      body: _isUrl
          ? EmptyState(
              icon: Icons.rss_feed,
              text: 'Ajouter ce flux RSS ?',
              action: FilledButton(onPressed: _lookupUrl, child: const Text('Ouvrir le flux')),
            )
          : !searching
              ? const _DiscoverHome()
              : AsyncView<List<SearchResult>>(
                  results,
                  onRetry: () => ref.invalidate(searchResultsProvider),
                  builder: (list) => list.isEmpty
                      ? const EmptyState(icon: Icons.search_off, text: 'Aucun résultat')
                      : ListView(children: [
                          const SectionHeader('Résultats'),
                          for (final r in list) SearchResultTile(r),
                        ]),
                ),
    );
  }
}

/// Shown when the search box is empty: themes, then the current top shows.
class _DiscoverHome extends ConsumerWidget {
  const _DiscoverHome();

  static const _cardH = 76.0;
  static const _cardW = 156.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final top = ref.watch(trendingProvider(null));
    return RefreshIndicator(
      onRefresh: () => ref.refresh(trendingProvider(null).future),
      child: ListView(children: [
        const SectionHeader('Thèmes'),
        SizedBox(
          height: 2 * _cardH + 8,
          child: GridView.count(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            crossAxisCount: 2,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: _cardH / _cardW,
            children: [
              for (final t in PodcastTheme.all)
                ThemeCard(t, onTap: () => context.push('/discover/theme/${t.genre}')),
            ],
          ),
        ),
        const SectionHeader('Tendances'),
        ...switch (top) {
          AsyncData(:final value) when value.isNotEmpty => [
              SizedBox(
                height: 200,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: value.length.clamp(0, 10),
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (_, i) => _TopCard(value[i], rank: i + 1),
                ),
              ),
              for (var i = 10; i < value.length; i++) SearchResultTile(value[i], rank: i + 1),
            ],
          AsyncLoading() => const [
              Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
            ],
          _ => [
              EmptyState(
                icon: Icons.trending_up,
                text: 'Tendances indisponibles',
                action: TextButton(
                  onPressed: () => ref.invalidate(trendingProvider(null)),
                  child: const Text('Réessayer'),
                ),
              ),
            ],
        },
        const SizedBox(height: 16),
      ]),
    );
  }
}

/// Top shows of one theme.
class ThemePage extends ConsumerWidget {
  const ThemePage({super.key, required this.genre});
  final String genre;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = PodcastTheme.byGenre(genre);
    return Scaffold(
      appBar: AppBar(
        title: Text(theme?.label ?? 'Thème'),
        backgroundColor: theme?.color.withValues(alpha: 0.25),
      ),
      body: AsyncView<List<SearchResult>>(
        ref.watch(trendingProvider(genre)),
        onRetry: () => ref.invalidate(trendingProvider(genre)),
        builder: (list) => list.isEmpty
            ? const EmptyState(icon: Icons.trending_up, text: 'Rien pour ce thème')
            : RefreshIndicator(
                onRefresh: () => ref.refresh(trendingProvider(genre).future),
                child: ListView(children: [
                  for (var i = 0; i < list.length; i++) SearchResultTile(list[i], rank: i + 1),
                ]),
              ),
      ),
    );
  }
}

/// Makes sure the server knows the feed, then opens it.
Future<void> openSearchResult(BuildContext context, WidgetRef ref, SearchResult r) async {
  try {
    final d = await ref.read(apiProvider).lookup(r.feedUrl);
    if (context.mounted) context.push('/podcast/${d.podcast.id}');
  } catch (e) {
    if (context.mounted) showError(context, e);
  }
}

class _TopCard extends ConsumerWidget {
  const _TopCard(this.r, {required this.rank});
  final SearchResult r;
  final int rank;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    return SizedBox(
      width: 132,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => openSearchResult(context, ref, r),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Stack(children: [
            Artwork(r.imageUrl, size: 132, radius: 12),
            Positioned(
              left: 6,
              top: 6,
              child: CircleAvatar(
                radius: 12,
                backgroundColor: Colors.black54,
                child: Text('$rank', style: const TextStyle(color: Colors.white, fontSize: 12)),
              ),
            ),
          ]),
          const SizedBox(height: 6),
          Text(r.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.labelLarge),
          if (r.author != null)
            Text(r.author!, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodySmall),
        ]),
      ),
    );
  }
}

class SearchResultTile extends ConsumerWidget {
  const SearchResultTile(this.r, {super.key, this.rank});
  final SearchResult r;
  final int? rank;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subscribed = ref.watch(subscribedIdsProvider).contains(r.podcastId);
    return ListTile(
      leading: Row(mainAxisSize: MainAxisSize.min, children: [
        if (rank != null)
          SizedBox(
            width: 28,
            child: Text('$rank',
                textAlign: TextAlign.center, style: Theme.of(context).textTheme.labelLarge),
          ),
        Artwork(r.imageUrl),
      ]),
      title: Text(r.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          if (r.author != null) r.author!,
          if (r.episodeCount != null) '${r.episodeCount} épisodes',
        ].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: subscribed
          ? const Icon(Icons.check_circle)
          : r.hasVideo
              ? const Icon(Icons.videocam_outlined)
              : null,
      onTap: () => openSearchResult(context, ref, r),
    );
  }
}
