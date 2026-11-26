import 'package:bettercast_core/bettercast_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../player/player_providers.dart';
import '../../ui/widgets.dart';

class FeedPage extends ConsumerWidget {
  const FeedPage({super.key});

  static String _greeting() {
    final h = DateTime.now().hour;
    if (h < 5) return 'Bonne nuit';
    if (h < 12) return 'Bonjour';
    if (h < 18) return 'Bon après-midi';
    return 'Bonsoir';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = ref.watch(newReleasesProvider);
    final resume = ref.watch(inProgressEpisodesProvider).value ?? const <FeedItem>[];
    final name = ref.watch(sessionProvider.select((s) => s.user?.displayName));
    final theme = Theme.of(context);
    Future<void> refresh() async {
      await ref.read(episodeStatesProvider.notifier).sync();
      ref.invalidate(subscriptionsProvider);
      return ref.refresh(newReleasesProvider.future);
    }

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: AsyncView(
          feed,
          onRetry: refresh,
          builder: (items) => RefreshIndicator(
            onRefresh: refresh,
            child: CustomScrollView(slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(
                          name == null || name.isEmpty ? _greeting() : '${_greeting()}, $name',
                          style: theme.textTheme.bodyLarge
                              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                        Text('Nouveautés', style: theme.textTheme.headlineMedium),
                      ]),
                    ),
                    const BrandMark(size: 44),
                  ]),
                ),
              ),
              if (resume.isNotEmpty) ...[
                const SliverToBoxAdapter(child: SectionHeader('Reprendre l’écoute')),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 132,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: resume.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 12),
                      itemBuilder: (_, i) => _ResumeCard(resume[i]),
                    ),
                  ),
                ),
              ],
              if (items.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 60),
                    child: EmptyState(
                      icon: Icons.auto_awesome_rounded,
                      text: 'Abonne-toi à des podcasts pour voir leurs nouveaux épisodes ici.',
                      action: FilledButton.icon(
                        onPressed: () => context.go('/discover'),
                        icon: const Icon(Icons.explore_rounded),
                        label: const Text('Découvrir'),
                      ),
                    ),
                  ),
                )
              else ...[
                const SliverToBoxAdapter(child: SectionHeader('Derniers épisodes')),
                SliverList.builder(
                  itemCount: items.length,
                  itemBuilder: (_, i) => EpisodeTile(items[i]),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

/// Wide card for an episode in progress: cover, title, time left, play.
class _ResumeCard extends ConsumerWidget {
  const _ResumeCard(this.item);
  final FeedItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = item.episode;
    final state = ref.watch(episodeStateProvider(e.id));
    final isCurrent = ref.watch(playerProvider.select((p) => p.current?.episode.id == e.id));
    final isPlaying = ref.watch(playerProvider.select((p) => p.playing)) && isCurrent;
    final theme = Theme.of(context);
    final s = theme.colorScheme;
    final total = e.duration;
    final progress = total != null && total.inSeconds > 0
        ? (state.position.inSeconds / total.inSeconds).clamp(0.0, 1.0)
        : null;
    return SizedBox(
      width: 290,
      child: Card(
        child: InkWell(
          onTap: () => context.push('/episode', extra: item),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Artwork(e.imageUrl ?? item.podcast.imageUrl, size: 84, radius: 16),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(item.podcast.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: s.primary, fontWeight: FontWeight.w800)),
                      Text(e.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(height: 1.2)),
                      const SizedBox(height: 6),
                      if (total != null)
                        Text('Reste ${formatDuration(total - state.position)}',
                            style: theme.textTheme.bodySmall?.copyWith(color: s.onSurfaceVariant)),
                    ]),
              ),
              const SizedBox(width: 8),
              PlayRingButton(
                playing: isPlaying,
                active: true,
                progress: progress,
                size: 48,
                onPressed: () {
                  final p = ref.read(playerProvider);
                  isCurrent ? p.playPause() : p.play(item);
                },
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
