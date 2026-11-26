import 'dart:ui';

import 'package:bettercast_core/bettercast_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auto_downloads.dart';
import '../../core/providers.dart';
import '../../ui/auto_download_sheet.dart';
import '../../ui/theme.dart';
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
    final cover = detail.value?.podcast.imageUrl;
    return ArtworkTheme(
      artworkUrl: cover,
      child: Builder(builder: (context) {
        return Scaffold(
          body: AsyncView<PodcastDetail>(
            detail,
            onRetry: () => ref.invalidate(podcastDetailProvider(widget.podcastId)),
            builder: (d) => _body(context, d),
          ),
        );
      }),
    );
  }

  Widget _body(BuildContext context, PodcastDetail d) {
    final subs = ref.watch(subscriptionsProvider).value ?? const <Subscription>[];
    final sub = subs.where((s) => s.podcast.id == widget.podcastId).firstOrNull;
    final states = ref.watch(episodeStatesProvider);
    final autoCount = ref.watch(autoDownloadsProvider.select((m) => m[widget.podcastId] ?? 0));
    final p = d.podcast;
    final subscribed = sub != null;
    final episodes = _hidePlayed
        ? d.episodes.where((e) => !(states[e.id]?.played ?? false)).toList()
        : d.episodes;
    final theme = Theme.of(context);
    final s = theme.colorScheme;
    final top = MediaQuery.paddingOf(context).top;

    return RefreshIndicator(
      onRefresh: () => ref.refresh(podcastDetailProvider(widget.podcastId).future),
      child: CustomScrollView(slivers: [
        SliverAppBar(
          pinned: true,
          stretch: true,
          expandedHeight: 330 + top,
          backgroundColor: s.surface,
          title: const SizedBox.shrink(),
          flexibleSpace: FlexibleSpaceBar(
            stretchModes: const [StretchMode.zoomBackground, StretchMode.blurBackground],
            background: _Hero(podcast: p, episodeCount: d.episodes.length,
                hasVideo: d.episodes.any((e) => e.hasVideo)),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: _busy
                        ? const Center(child: CircularProgressIndicator())
                        : subscribed
                            ? OutlinedButton.icon(
                                key: const ValueKey('sub'),
                                onPressed: () => _toggleSubscription(true),
                                icon: const Icon(Icons.check_rounded),
                                label: const Text('Abonné'),
                              )
                            : FilledButton.icon(
                                key: const ValueKey('unsub'),
                                onPressed: () => _toggleSubscription(false),
                                icon: const Icon(Icons.add_rounded),
                                label: const Text("S'abonner"),
                              ),
                  ),
                ),
                if (subscribed) ...[
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: sub.notify ? 'Couper les notifications' : 'Activer les notifications',
                    icon: Icon(sub.notify
                        ? Icons.notifications_active_rounded
                        : Icons.notifications_off_outlined),
                    onPressed: () async {
                      await ref.read(apiProvider).setNotify(p.id, !sub.notify);
                      ref.invalidate(subscriptionsProvider);
                    },
                  ),
                ],
              ]),
              const SizedBox(height: 12),
              _AutoDownloadCard(
                count: autoCount,
                enabled: subscribed,
                onTap: () => showAutoDownloadSheet(context, p),
              ),
              if (p.description.isNotEmpty) ...[
                const SizedBox(height: 16),
                _ExpandableText(plainText(p.description)),
              ],
            ]),
          ),
        ),
        SliverToBoxAdapter(
          child: SectionHeader(
            'Épisodes',
            action: FilterChip(
              label: const Text('Masquer écoutés'),
              selected: _hidePlayed,
              onSelected: (v) => setState(() => _hidePlayed = v),
            ),
          ),
        ),
        SliverList.builder(
          itemCount: episodes.length,
          itemBuilder: (_, i) =>
              EpisodeTile(FeedItem(episode: episodes[i], podcast: p), showPodcast: false),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ]),
    );
  }
}

/// Blurred cover backdrop with the artwork and title on top.
class _Hero extends StatelessWidget {
  const _Hero({required this.podcast, required this.episodeCount, required this.hasVideo});
  final Podcast podcast;
  final int episodeCount;
  final bool hasVideo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = theme.colorScheme;
    final p = podcast;
    final top = MediaQuery.paddingOf(context).top;
    return Stack(fit: StackFit.expand, children: [
      if (p.imageUrl != null && p.imageUrl!.isNotEmpty)
        ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
          child: Image.network(p.imageUrl!, fit: BoxFit.cover, cacheWidth: 200,
              errorBuilder: (_, _, _) => const SizedBox()),
        ),
      DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              s.primary.withValues(alpha: 0.35),
              s.surface.withValues(alpha: 0.55),
              s.surface,
            ],
            stops: const [0, 0.55, 1],
          ),
        ),
      ),
      Padding(
        padding: EdgeInsets.fromLTRB(24, top + 48, 24, 12),
        child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
          Hero(
            tag: 'cover-${p.id}',
            child: Artwork(p.imageUrl, size: 172, radius: 28, shadow: true),
          ),
          const SizedBox(height: 18),
          Text(p.title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
          if (p.author != null) ...[
            const SizedBox(height: 2),
            Text(p.author!,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(color: s.primary, fontWeight: FontWeight.w600)),
          ],
          const SizedBox(height: 10),
          Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 4, children: [
            if (p.isPremium)
              const Badge2('Patreon', icon: Icons.star_rounded, color: premiumColor),
            if (hasVideo) const Badge2('Vidéo', icon: Icons.videocam_rounded),
            Badge2('$episodeCount épisodes', icon: Icons.mic_rounded),
          ]),
        ]),
      ),
    ]);
  }
}

class _AutoDownloadCard extends StatelessWidget {
  const _AutoDownloadCard({required this.count, required this.enabled, required this.onTap});
  final int count;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = theme.colorScheme;
    final on = enabled && count > 0;
    return Card(
      color: on ? s.primary.withValues(alpha: 0.14) : s.surfaceContainer,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(children: [
            Icon(on ? Icons.download_for_offline_rounded : Icons.download_for_offline_outlined,
                color: enabled ? s.primary : s.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Téléchargement automatique', style: theme.textTheme.titleSmall),
                Text(
                  !enabled
                      ? 'Abonne-toi pour garder les derniers épisodes hors ligne'
                      : count == 0
                          ? 'Désactivé'
                          : '${autoDownloadLabel(count)} épisode${count > 1 ? 's' : ''}',
                  style: theme.textTheme.bodySmall?.copyWith(color: s.onSurfaceVariant),
                ),
              ]),
            ),
            if (enabled) Icon(Icons.chevron_right_rounded, color: s.onSurfaceVariant),
          ]),
        ),
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => setState(() => _open = !_open),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 250),
        alignment: Alignment.topCenter,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            widget.text,
            maxLines: _open ? null : 3,
            overflow: _open ? null : TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant, height: 1.45),
          ),
          Text(_open ? 'Moins' : 'Plus',
              style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary)),
        ]),
      ),
    );
  }
}
