import 'package:bettercast_core/bettercast_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/downloads.dart';
import '../../core/auto_downloads.dart';
import '../../core/providers.dart';
import '../../ui/auto_download_sheet.dart';
import '../../ui/widgets.dart';

class LibraryPage extends ConsumerWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => DefaultTabController(
        length: 4,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Bibliothèque'),
            bottom: const TabBar(
                isScrollable: true,
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                tabs: [
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
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 170,
              mainAxisSpacing: 18,
              crossAxisSpacing: 16,
              childAspectRatio: 0.74,
            ),
            itemCount: sorted.length,
            itemBuilder: (_, i) => _SubscriptionTile(sorted[i].podcast),
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
              child: ListView.builder(
                itemCount: items.length,
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
    return ListView.builder(
      itemCount: downloads.length,
            itemBuilder: (_, i) => EpisodeTile(downloads[i].item),
    );
  }
}

class _SubscriptionTile extends ConsumerWidget {
  const _SubscriptionTile(this.podcast);
  final Podcast podcast;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = podcast;
    final auto = ref.watch(autoDownloadsProvider.select((m) => m[p.id] ?? 0));
    final theme = Theme.of(context);
    return GestureDetector(
      onLongPress: () => showAutoDownloadSheet(context, p),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => context.push('/podcast/${p.id}'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AspectRatio(
            aspectRatio: 1,
            child: Stack(fit: StackFit.expand, children: [
              LayoutBuilder(
                  builder: (_, c) => Artwork(p.imageUrl, size: c.maxWidth, radius: 20, shadow: true)),
              if (p.isPremium)
                const Positioned(
                  top: 8,
                  left: 8,
                  child: _Pill(icon: Icons.star_rounded, color: premiumColor),
                ),
              if (auto > 0)
                Positioned(
                  bottom: 8,
                  right: 8,
                  child: _Pill(icon: Icons.download_rounded, label: '$auto',
                      color: theme.colorScheme.primary),
                ),
            ]),
          ),
          const SizedBox(height: 8),
          Text(p.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(height: 1.2)),
        ]),
      ),
    );
  }
}

/// Small glassy marker drawn over a cover.
class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.color, this.label});
  final IconData icon;
  final Color color;
  final String? label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: color),
          if (label != null) ...[
            const SizedBox(width: 3),
            Text(label!, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
          ],
        ]),
      );
}
