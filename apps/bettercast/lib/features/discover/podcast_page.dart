import 'package:bettercast_core/bettercast_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auto_downloads.dart';
import '../../core/providers.dart';
import '../../ui/widgets.dart';

class PodcastPage extends ConsumerStatefulWidget {
  const PodcastPage({super.key, required this.podcastId});
  final String podcastId;

  @override
  ConsumerState<PodcastPage> createState() => _PodcastPageState();
}

class _PodcastPageState extends ConsumerState<PodcastPage> {
  bool _busy = false;
  bool _hidePlayed = false;

  Future<void> _toggleSubscription(bool subscribed) async {
    setState(() => _busy = true);
    final api = ref.read(apiProvider);
    try {
      subscribed
          ? await api.unsubscribe(widget.podcastId)
          : await api.subscribe(widget.podcastId);
      ref.invalidate(subscriptionsProvider);
      ref.invalidate(newReleasesProvider);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(podcastDetailProvider(widget.podcastId));
    final subs = ref.watch(subscriptionsProvider).value ?? const <Subscription>[];
    final sub = subs.where((s) => s.podcast.id == widget.podcastId).firstOrNull;
    final states = ref.watch(episodeStatesProvider);
    final autoCount = ref.watch(autoDownloadsProvider.select((m) => m[widget.podcastId] ?? 0));

    return Scaffold(
      body: AsyncView<PodcastDetail>(
        detail,
        onRetry: () => ref.invalidate(podcastDetailProvider(widget.podcastId)),
        builder: (d) {
          final p = d.podcast;
          final subscribed = sub != null;
          final episodes = _hidePlayed
              ? d.episodes.where((e) => !(states[e.id]?.played ?? false)).toList()
              : d.episodes;
          final theme = Theme.of(context);
          return RefreshIndicator(
            onRefresh: () => ref.refresh(podcastDetailProvider(widget.podcastId).future),
            child: CustomScrollView(slivers: [
              SliverAppBar(
                pinned: true,
                title: Text(p.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                actions: [
                  if (subscribed)
                    IconButton(
                      tooltip: sub.notify ? 'Couper les notifications' : 'Activer les notifications',
                      icon: Icon(sub.notify
                          ? Icons.notifications_active
                          : Icons.notifications_off_outlined),
                      onPressed: () async {
                        await ref.read(apiProvider).setNotify(p.id, !sub.notify);
                        ref.invalidate(subscriptionsProvider);
                      },
                    ),
                  if (subscribed)
                    PopupMenuButton<int>(
                      tooltip: 'Téléchargement automatique',
                      icon: Icon(autoCount > 0
                          ? Icons.download_for_offline
                          : Icons.download_for_offline_outlined),
                      initialValue: autoCount,
                      onSelected: (n) {
                        ref.read(autoDownloadsProvider.notifier).set(p.id, n);
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(switch (n) {
                          0 => 'Téléchargement automatique désactivé',
                          1 => 'Le dernier épisode sera toujours disponible hors ligne',
                          _ => 'Les $n derniers épisodes seront toujours disponibles hors ligne',
                        })));
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                            enabled: false, child: Text('Téléchargement automatique')),
                        for (final (n, label) in const [
                          (0, 'Désactivé'),
                          (1, 'Dernier épisode'),
                          (2, '2 derniers épisodes'),
                        ])
                          CheckedPopupMenuItem(
                              value: n, checked: autoCount == n, child: Text(label)),
                      ],
                    ),
                  PopupMenuButton<String>(
                    onSelected: (v) => setState(() => _hidePlayed = !_hidePlayed),
                    itemBuilder: (_) => [
                      CheckedPopupMenuItem(
                        value: 'played',
                        checked: _hidePlayed,
                        child: const Text('Masquer les épisodes écoutés'),
                      ),
                    ],
                  ),
                ],
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Artwork(p.imageUrl, size: 120, radius: 12),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(p.title, style: theme.textTheme.titleLarge),
                          if (p.author != null)
                            Text(p.author!, style: theme.textTheme.bodyMedium),
                          const SizedBox(height: 8),
                          Wrap(spacing: 6, runSpacing: 4, children: [
                            if (p.isPremium)
                              const Badge2('Patreon', icon: Icons.star, color: premiumColor),
                            if (d.episodes.any((e) => e.hasVideo))
                              const Badge2('Vidéo', icon: Icons.videocam),
                            Badge2('${d.episodes.length} épisodes'),
                          ]),
                          const SizedBox(height: 12),
                          _busy
                              ? const CircularProgressIndicator()
                              : subscribed
                                  ? OutlinedButton.icon(
                                      onPressed: () => _toggleSubscription(true),
                                      icon: const Icon(Icons.check),
                                      label: const Text('Abonné'),
                                    )
                                  : FilledButton.icon(
                                      onPressed: () => _toggleSubscription(false),
                                      icon: const Icon(Icons.add),
                                      label: const Text("S'abonner"),
                                    ),
                        ]),
                      ),
                    ]),
                    if (p.description.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _ExpandableText(plainText(p.description)),
                    ],
                  ]),
                ),
              ),
              SliverList.separated(
                itemCount: episodes.length,
                separatorBuilder: (_, _) => const Divider(height: 1, indent: 92),
                itemBuilder: (_, i) =>
                    EpisodeTile(FeedItem(episode: episodes[i], podcast: p), showPodcast: false),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ]),
          );
        },
      ),
    );
  }
}

class _ExpandableText extends StatefulWidget {
  const _ExpandableText(this.text);
  final String text;

  @override
  State<_ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<_ExpandableText> {
  bool _open = false;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () => setState(() => _open = !_open),
        child: Text(
          widget.text,
          maxLines: _open ? null : 3,
          overflow: _open ? null : TextOverflow.ellipsis,
        ),
      );
}
