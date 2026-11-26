import 'package:bettercast_core/bettercast_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../core/api_client.dart';
import '../core/downloads.dart';
import '../core/providers.dart';
import '../player/player_providers.dart';

String formatDuration(Duration? d) {
  if (d == null) return '';
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  if (h > 0) return '$h h ${m.toString().padLeft(2, '0')}';
  if (m > 0) return '$m min';
  return '$s s';
}

String formatClock(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

String formatDate(DateTime? d) {
  if (d == null) return '';
  final local = d.toLocal();
  final now = DateTime.now();
  final days = DateTime(now.year, now.month, now.day)
      .difference(DateTime(local.year, local.month, local.day))
      .inDays;
  if (days == 0) return "Aujourd'hui";
  if (days == 1) return 'Hier';
  if (days < 7) return 'Il y a $days jours';
  return DateFormat.yMMMd('fr_FR').format(local);
}

/// Strips HTML for one-line previews.
String plainText(String html) => html
    .replaceAll(RegExp(r'<br\s*/?>|</p>', caseSensitive: false), ' ')
    .replaceAll(RegExp(r'<[^>]+>'), '')
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

class Artwork extends StatelessWidget {
  const Artwork(this.url, {super.key, this.size = 56, this.radius = 8});
  final String? url;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: size,
      height: size,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Icon(Icons.podcasts, size: size * 0.5),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: url == null || url!.isEmpty
          ? placeholder
          : Image.network(
              url!,
              width: size,
              height: size,
              fit: BoxFit.cover,
              cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
              errorBuilder: (_, _, _) => placeholder,
            ),
    );
  }
}

class Badge2 extends StatelessWidget {
  const Badge2(this.label, {super.key, this.icon, this.color});
  final String label;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.secondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 12, color: c), const SizedBox(width: 3)],
        Text(label, style: TextStyle(fontSize: 11, color: c, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

const premiumColor = Color(0xFFFF7A59);

List<Widget> episodeBadges(Episode e) => [
      if (e.premium) const Badge2('Premium', icon: Icons.star, color: premiumColor),
      if (e.hasVideo) const Badge2('Vidéo', icon: Icons.videocam),
    ];

/// One episode row with progress, like and play.
class EpisodeTile extends ConsumerWidget {
  const EpisodeTile(this.item, {super.key, this.showPodcast = true});
  final FeedItem item;
  final bool showPodcast;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = item.episode;
    final state = ref.watch(episodeStateProvider(e.id));
    final download = ref.watch(downloadsProvider.select((m) => m[e.id]));
    final isCurrent = ref.watch(playerProvider.select((p) => p.current?.episode.id == e.id));
    final theme = Theme.of(context);
    final total = e.duration;
    final progress = total != null && total.inSeconds > 0 && state.inProgress
        ? state.position.inSeconds / total.inSeconds
        : null;
    final meta = [
      formatDate(e.publishedAt),
      if (state.inProgress && total != null)
        'Reste ${formatDuration(total - state.position)}'
      else
        formatDuration(total),
    ].where((s) => s.isNotEmpty).join(' · ');

    return InkWell(
      onTap: () => context.push('/episode', extra: item),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Artwork(e.imageUrl ?? item.podcast.imageUrl, size: 64),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (showPodcast)
                Text(item.podcast.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium
                        ?.copyWith(color: theme.colorScheme.primary)),
              Text(e.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: state.played ? theme.disabledColor : null,
                  )),
              const SizedBox(height: 4),
              Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(meta, style: theme.textTheme.bodySmall),
                ...episodeBadges(e),
                if (download?.isComplete ?? false)
                  Icon(Icons.download_done, size: 14, color: theme.colorScheme.primary),
                if (state.played) const Icon(Icons.check, size: 14),
              ]),
              if (progress != null) ...[
                const SizedBox(height: 6),
                LinearProgressIndicator(value: progress.clamp(0, 1), minHeight: 3),
              ],
            ]),
          ),
          Column(children: [
            IconButton(
              tooltip: state.liked ? 'Retirer des likés' : 'Liker',
              icon: Icon(state.liked ? Icons.favorite : Icons.favorite_border,
                  color: state.liked ? Colors.redAccent : null),
              onPressed: () => ref.read(episodeStatesProvider.notifier).toggleLike(e),
            ),
            IconButton.filledTonal(
              tooltip: 'Lire',
              icon: Icon(isCurrent ? Icons.graphic_eq : Icons.play_arrow),
              onPressed: () => ref.read(playerProvider).play(item),
            ),
          ]),
        ]),
      ),
    );
  }
}

/// Standard loading / error / data rendering with pull-to-refresh retry.
class AsyncView<T> extends StatelessWidget {
  const AsyncView(this.value, {super.key, required this.builder, this.onRetry});
  final AsyncValue<T> value;
  final Widget Function(T) builder;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return value.when(
      skipLoadingOnRefresh: true,
      skipLoadingOnReload: true,
      data: builder,
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(e is ApiException && e.isOffline ? Icons.cloud_off : Icons.error_outline, size: 40),
            const SizedBox(height: 12),
            Text('$e', textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              FilledButton.tonal(onPressed: onRetry, child: const Text('Réessayer')),
            ],
          ]),
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.text, this.action});
  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 48, color: Theme.of(context).disabledColor),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ]),
        ),
      );
}

void showError(BuildContext context, Object e) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
}
