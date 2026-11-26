import 'package:bettercast_core/bettercast_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/downloads.dart';
import '../../core/providers.dart';
import '../../ui/widgets.dart';

class LibraryPage extends ConsumerWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => DefaultTabController(
        length: 4,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Bibliothèque'),
            bottom: const TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [
              Tab(text: 'Abonnements'),
              Tab(text: 'En cours'),
              Tab(text: 'Likés'),
              Tab(text: 'Téléchargés'),
            ]),
          ),
          body: const TabBarView(children: [
            _Subscriptions(),
            _EpisodeList(kind: _Kind.inProgress),
            _EpisodeList(kind: _Kind.liked),
            _Downloads(),
          ]),
        ),
      );
}

class _Subscriptions extends ConsumerWidget {
  const _Subscriptions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subs = ref.watch(subscriptionsProvider);
    return AsyncView<List<Subscription>>(
      subs,
      onRetry: () => ref.invalidate(subscriptionsProvider),
      builder: (list) {
        if (list.isEmpty) {
          return const EmptyState(icon: Icons.podcasts, text: 'Aucun abonnement pour le moment.');
        }
        final sorted = [...list]
          ..sort((a, b) => a.podcast.title.toLowerCase().compareTo(b.podcast.title.toLowerCase()));
        return RefreshIndicator(
          onRefresh: () => ref.refresh(subscriptionsProvider.future),
          child: GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 160,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.78,
            ),
            itemCount: sorted.length,
            itemBuilder: (_, i) {
              final p = sorted[i].podcast;
              return InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => context.push('/podcast/${p.id}'),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  AspectRatio(
                    aspectRatio: 1,
                    child: Stack(fit: StackFit.expand, children: [
                      LayoutBuilder(
                          builder: (_, c) => Artwork(p.imageUrl, size: c.maxWidth, radius: 12)),
                      if (p.isPremium)
                        const Positioned(
                          top: 6,
                          right: 6,
                          child: Badge2('Patreon', icon: Icons.star, color: premiumColor),
                        ),
                    ]),
                  ),
                  const SizedBox(height: 6),
                  Text(p.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium),
                ]),
              );
            },
          ),
        );
      },
    );
  }
}

enum _Kind { inProgress, liked }

class _EpisodeList extends ConsumerWidget {
  const _EpisodeList({required this.kind});
  final _Kind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = kind == _Kind.liked ? likedEpisodesProvider : inProgressEpisodesProvider;
    return AsyncView<List<FeedItem>>(
      ref.watch(provider),
      onRetry: () => ref.invalidate(provider),
      builder: (items) => items.isEmpty
          ? EmptyState(
              icon: kind == _Kind.liked ? Icons.favorite_border : Icons.timelapse,
              text: kind == _Kind.liked
                  ? 'Les épisodes que tu likes apparaîtront ici.'
                  : 'Aucun épisode en cours.',
            )
          : RefreshIndicator(
              onRefresh: () => ref.read(episodeStatesProvider.notifier).sync(),
              child: ListView.separated(
                itemCount: items.length,
                separatorBuilder: (_, _) => const Divider(height: 1, indent: 92),
                itemBuilder: (_, i) => EpisodeTile(items[i]),
              ),
            ),
    );
  }
}

class _Downloads extends ConsumerWidget {
  const _Downloads();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloads = ref.watch(downloadsProvider).values.toList().reversed.toList();
    if (downloads.isEmpty) {
      return const EmptyState(
          icon: Icons.download_outlined, text: 'Télécharge des épisodes pour les écouter hors-ligne.');
    }
    return ListView.separated(
      itemCount: downloads.length,
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 92),
      itemBuilder: (_, i) => EpisodeTile(downloads[i].item),
    );
  }
}
