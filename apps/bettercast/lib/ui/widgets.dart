import 'package:bettercast_core/bettercast_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../core/api_client.dart';
import '../core/connectivity.dart';
import '../core/downloads.dart';
import '../core/providers.dart';
import '../player/player_providers.dart';
import 'theme.dart';

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

/// Cover art with a soft shadow and a branded placeholder.
class Artwork extends StatelessWidget {
  const Artwork(this.url, {super.key, this.size = 56, this.radius, this.shadow = false});
  final String? url;
  final double size;
  final double? radius;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final r = radius ?? (size * 0.18).clamp(8.0, 28.0);
    final placeholder = Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(gradient: Brand.gradient),
      child: Icon(Icons.podcasts, size: size * 0.45, color: Colors.white.withValues(alpha: 0.9)),
    );
    final image = ClipRRect(
      borderRadius: BorderRadius.circular(r),
      child: url == null || url!.isEmpty
          ? placeholder
          : Image(
              image: ResizeImage(artworkImage(url!),
                  width: (size * MediaQuery.devicePixelRatioOf(context)).round()),
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => placeholder,
              frameBuilder: (_, child, frame, sync) => sync
                  ? child
                  : AnimatedOpacity(
                      opacity: frame == null ? 0 : 1,
                      duration: const Duration(milliseconds: 250),
                      child: child,
                    ),
            ),
    );
    if (!shadow) return image;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: size * 0.18,
            offset: Offset(0, size * 0.06),
          ),
        ],
      ),
      child: image,
    );
  }
}

/// The BetterCast logo: a glowing ember tile with a waveform.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 56});
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: Brand.gradient,
          borderRadius: BorderRadius.circular(size * 0.3),
          boxShadow: [
            BoxShadow(
              color: Brand.ember.withValues(alpha: 0.45),
              blurRadius: size * 0.4,
              offset: Offset(0, size * 0.1),
            ),
          ],
        ),
        child: Icon(Icons.graphic_eq_rounded, color: Colors.white, size: size * 0.6),
      );
}

/// Big section title, with an optional trailing action.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.text, {super.key, this.action, this.padding});
  final String text;
  final Widget? action;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) => Padding(
        padding: padding ?? const EdgeInsets.fromLTRB(20, 24, 12, 10),
        child: Row(children: [
          Expanded(
            child: Text(text,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800)),
          ),
          ?action,
        ]),
      );
}

class Badge2 extends StatelessWidget {
  const Badge2(this.label, {super.key, this.icon, this.color});
  final String label;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.tertiary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 12, color: c), const SizedBox(width: 4)],
        Text(label, style: TextStyle(fontSize: 11, color: c, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

const premiumColor = Brand.gold;

List<Widget> episodeBadges(Episode e) => [
      if (e.premium) const Badge2('Premium', icon: Icons.star_rounded, color: premiumColor),
      if (e.hasVideo) const Badge2('Vidéo', icon: Icons.videocam_rounded),
    ];

/// Round play button wrapped in a ring that shows listening progress.
class PlayRingButton extends StatelessWidget {
  const PlayRingButton({
    super.key,
    required this.playing,
    required this.onPressed,
    this.progress,
    this.size = 44,
    this.active = false,
  });
  final bool playing;
  final bool active;
  final double? progress;
  final double size;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(alignment: Alignment.center, children: [
        SizedBox.expand(
          child: CircularProgressIndicator(
            value: progress ?? 0,
            strokeWidth: 3,
            strokeCap: StrokeCap.round,
            backgroundColor: s.onSurface.withValues(alpha: 0.10),
            color: s.primary,
          ),
        ),
        Material(
          color: active ? s.primary : s.primary.withValues(alpha: 0.14),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: SizedBox(
              width: size - 10,
              height: size - 10,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                child: Icon(
                  playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  key: ValueKey(playing),
                  size: size * 0.5,
                  color: active ? s.onPrimary : s.primary,
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

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
    final isPlaying = ref.watch(playerProvider.select((p) => p.playing)) && isCurrent;
    final theme = Theme.of(context);
    final s = theme.colorScheme;
    final total = e.duration;
    final progress = total != null && total.inSeconds > 0 && (state.inProgress || isCurrent)
        ? (state.position.inSeconds / total.inSeconds).clamp(0.0, 1.0)
        : state.played
            ? 1.0
            : null;
    final meta = [
      formatDate(e.publishedAt),
      if (state.inProgress && total != null)
        'Reste ${formatDuration(total - state.position)}'
      else
        formatDuration(total),
    ].where((t) => t.isNotEmpty).join(' · ');
    // Offline, only downloaded episodes can play.
    final unavailable = !ref.watch(onlineProvider) && !(download?.isComplete ?? false);
    final muted = (state.played && !isCurrent) || unavailable;

    return InkWell(
      onTap: () => context.push('/episode', extra: item),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Opacity(
            opacity: muted ? 0.5 : 1,
            child: Artwork(e.imageUrl ?? item.podcast.imageUrl, size: 68, radius: 16),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (showPodcast)
                Text(item.podcast.title.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: s.primary,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    )),
              const SizedBox(height: 2),
              Text(e.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    height: 1.25,
                    color: muted ? s.onSurfaceVariant : null,
                  )),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(meta, style: theme.textTheme.bodySmall?.copyWith(color: s.onSurfaceVariant)),
                ...episodeBadges(e),
                if (download?.isComplete ?? false)
                  Icon(Icons.offline_pin_rounded, size: 15, color: s.secondary),
                if (state.played) Icon(Icons.done_all_rounded, size: 15, color: s.onSurfaceVariant),
              ]),
            ]),
          ),
          const SizedBox(width: 8),
          Column(mainAxisSize: MainAxisSize.min, children: [
            PlayRingButton(
              playing: isPlaying,
              active: isCurrent,
              progress: progress,
              onPressed: () {
                final p = ref.read(playerProvider);
                isCurrent ? p.playPause() : p.play(item);
              },
            ),
            const SizedBox(height: 2),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: state.liked ? 'Retirer des likés' : 'Liker',
              icon: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                child: Icon(
                  state.liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  key: ValueKey(state.liked),
                  size: 20,
                  color: state.liked ? Brand.ember : s.onSurfaceVariant,
                ),
              ),
              onPressed: () => ref.read(episodeStatesProvider.notifier).toggleLike(e),
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
      loading: () => const Center(child: CircularProgressIndicator(strokeCap: StrokeCap.round)),
      error: (e, _) => EmptyState(
        icon: e is ApiException && e.isOffline ? Icons.cloud_off_rounded : Icons.error_outline_rounded,
        text: '$e',
        action: onRetry == null
            ? null
            : FilledButton.tonal(onPressed: onRetry, child: const Text('Réessayer')),
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
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [s.primary.withValues(alpha: 0.22), s.secondary.withValues(alpha: 0.10)],
              ),
            ),
            child: Icon(icon, size: 40, color: s.primary),
          ),
          const SizedBox(height: 18),
          Text(text,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: s.onSurfaceVariant)),
          if (action != null) ...[const SizedBox(height: 18), action!],
        ]),
      ),
    );
  }
}

void showError(BuildContext context, Object e) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
}

/// Thin strip shown while the server can't be reached.
class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(onlineProvider);
    final s = Theme.of(context).colorScheme;
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      child: online
          ? const SizedBox(width: double.infinity)
          : Material(
              color: s.secondaryContainer,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Row(children: [
                  Icon(Icons.cloud_off_rounded, size: 16, color: s.onSecondaryContainer),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Hors ligne · épisodes téléchargés uniquement',
                        style: Theme.of(context)
                            .textTheme
                            .labelMedium
                            ?.copyWith(color: s.onSecondaryContainer)),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        foregroundColor: s.onSecondaryContainer),
                    onPressed: () => ref.read(onlineProvider.notifier).probe(),
                    child: const Text('Réessayer'),
                  ),
                ]),
              ),
            ),
    );
  }
}

/// "Back 15 s" icon (Material only ships replay 5/10/30).
class Replay15Icon extends StatelessWidget {
  const Replay15Icon({super.key});

  @override
  Widget build(BuildContext context) {
    final icon = IconTheme.of(context);
    final size = icon.size ?? 24;
    return SizedBox.square(
      dimension: size,
      child: Stack(alignment: Alignment.center, children: [
        Icon(Icons.replay_rounded, size: size),
        Padding(
          padding: EdgeInsets.only(top: size * 0.12),
          child: Text(
            '15',
            style: TextStyle(
              fontSize: size * 0.3,
              fontWeight: FontWeight.w800,
              height: 1,
              color: icon.color,
            ),
          ),
        ),
      ]),
    );
  }
}
