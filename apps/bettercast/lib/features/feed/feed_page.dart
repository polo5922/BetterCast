import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../ui/widgets.dart';

class FeedPage extends ConsumerWidget {
  const FeedPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = ref.watch(newReleasesProvider);
    Future<void> refresh() async {
      await ref.read(episodeStatesProvider.notifier).sync();
      ref.invalidate(subscriptionsProvider);
      return ref.refresh(newReleasesProvider.future);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Nouveautés')),
      body: AsyncView(
        feed,
        onRetry: refresh,
        builder: (items) => RefreshIndicator(
          onRefresh: refresh,
          child: items.isEmpty
              ? ListView(children: [
                  const SizedBox(height: 80),
                  EmptyState(
                    icon: Icons.inbox_outlined,
                    text: 'Abonne-toi à des podcasts pour voir leurs nouveaux épisodes ici.',
                    action: FilledButton.icon(
                      onPressed: () => context.go('/discover'),
                      icon: const Icon(Icons.search),
                      label: const Text('Découvrir'),
                    ),
                  ),
                ])
              : ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const Divider(height: 1, indent: 92),
                  itemBuilder: (_, i) => EpisodeTile(items[i]),
                ),
        ),
      ),
    );
  }
}
