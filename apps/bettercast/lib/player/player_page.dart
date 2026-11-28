import 'package:bettercast_core/bettercast_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../core/providers.dart';
import '../ui/desktop/adaptive.dart';
import '../ui/motion.dart';
import '../ui/theme.dart';
import 'mini_player.dart';
import '../ui/widgets.dart';
import 'player_controller.dart';
import 'player_providers.dart';

class PlayerPage extends ConsumerWidget {
  const PlayerPage({super.key, this.embedded = false});

  /// Shown in the desktop side panel instead of as a full-screen page.
  final bool embedded;

  static const rates = [0.8, 1.0, 1.2, 1.5, 1.75, 2.0, 2.5];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = ref.watch(playerProvider.select((p) => p.current));
    if (item == null) {
      return Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: !embedded,
          actions: [
            if (embedded)
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => ref.read(playerPanelProvider.notifier).hide(),
              ),
          ],
        ),
        body: const EmptyState(icon: Icons.headphones_rounded, text: 'Rien en lecture'),
      );
    }
    return ArtworkTheme(
      artworkUrl: item.episode.imageUrl ?? item.podcast.imageUrl,
      child: Builder(builder: (context) => _build(context, ref)),
    );
  }

  Widget _build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(playerProvider);
    final item = p.current!;
    final theme = Theme.of(context);
    final s = theme.colorScheme;
    final e = item.episode;
    final liked = ref.watch(episodeStateProvider(e.id)).liked;
    final cover = e.imageUrl ?? item.podcast.imageUrl;

    final media = p.isVideo
        ? AspectRatio(
            aspectRatio: 16 / 9,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Video(controller: p.videoController, controls: MaterialVideoControls),
            ),
          )
        : LayoutBuilder(
            builder: (_, c) => Center(
              child: AnimatedScale(
                scale: p.playing ? 1 : 0.86,
                duration: const Duration(milliseconds: 450),
                curve: Curves.easeOutBack,
                child: HeroMode(
                  enabled: !embedded,
                  child: Hero(
                    tag: nowPlayingHeroTag,
                    child: Artwork(cover,
                        size: c.biggest.shortestSide.clamp(120.0, 380.0), radius: 28, shadow: true),
                  ),
                ),
              ),
            ),
          );

    final page = Scaffold(
      backgroundColor: s.surface,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: embedded
            ? IconButton(
                tooltip: 'Fermer le panneau',
                icon: const Icon(Icons.close_rounded),
                onPressed: () => ref.read(playerPanelProvider.notifier).hide(),
              )
            : IconButton(
                icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32),
                onPressed: () => context.pop(),
              ),
        centerTitle: true,
        title: Column(children: [
          Text('EN LECTURE',
              style: theme.textTheme.labelSmall
                  ?.copyWith(letterSpacing: 2, color: s.onSurfaceVariant, fontWeight: FontWeight.w800)),
          Text(item.podcast.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall),
        ]),
        actions: [
          IconButton(
            tooltip: "Détails de l'épisode",
            icon: const Icon(Icons.info_outline_rounded),
            onPressed: () => context.push('/episode', extra: item),
          ),
          IconButton(
            tooltip: "File d'attente",
            icon: Badge(
              isLabelVisible: p.queue.isNotEmpty,
              label: Text('${p.queue.length}'),
              child: const Icon(Icons.queue_music_rounded),
            ),
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              builder: (_) => const QueueList(),
            ),
          ),
        ],
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [s.primary.withValues(alpha: 0.45), s.primaryContainer.withValues(alpha: 0.25), s.surface],
            stops: const [0, 0.45, 0.9],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(children: [
                  const SizedBox(height: 16),
                  Expanded(child: Center(child: media)),
                  const SizedBox(height: 28),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(e.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, height: 1.15)),
                        const SizedBox(height: 4),
                        Text(item.podcast.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(color: s.primary, fontWeight: FontWeight.w700)),
                        if (episodeBadges(e).isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Wrap(spacing: 6, children: episodeBadges(e)),
                        ],
                      ]),
                    ),
                    IconButton(
                      iconSize: 28,
                      tooltip: liked ? 'Retirer des likés' : 'Liker',
                      icon: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                        child: Icon(
                          liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                          key: ValueKey(liked),
                          color: liked ? Brand.ember : null,
                        ),
                      ),
                      onPressed: () => ref.read(episodeStatesProvider.notifier).toggleLike(e),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  _SeekBar(p),
                  const SizedBox(height: 4),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                    IconButton(
                      iconSize: 36,
                      tooltip: 'Reculer de 15 s',
                      icon: const Icon(Icons.replay_10_rounded),
                      onPressed: () => p.skip(const Duration(seconds: -15)),
                    ),
                    _BigPlayButton(playing: p.playing, buffering: p.buffering, onPressed: p.playPause),
                    IconButton(
                      iconSize: 36,
                      tooltip: 'Avancer de 30 s',
                      icon: const Icon(Icons.forward_30_rounded),
                      onPressed: () => p.skip(const Duration(seconds: 30)),
                    ),
                  ]),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: s.onSurface.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                      PopupMenuButton<double>(
                        tooltip: 'Vitesse',
                        initialValue: p.rate,
                        onSelected: p.setRate,
                        itemBuilder: (_) => [
                          for (final r in rates) PopupMenuItem(value: r, child: Text('${r}x')),
                        ],
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text('${p.rate}x', style: theme.textTheme.labelLarge),
                        ),
                      ),
                      if (e.canSwitchMedia)
                        SegmentedButton<MediaKind>(
                          showSelectedIcon: false,
                          style: const ButtonStyle(visualDensity: VisualDensity.compact),
                          segments: const [
                            ButtonSegment(value: MediaKind.audio, icon: Icon(Icons.headphones_rounded)),
                            ButtonSegment(value: MediaKind.video, icon: Icon(Icons.videocam_rounded)),
                          ],
                          selected: {p.isVideo ? MediaKind.video : MediaKind.audio},
                          onSelectionChanged: (sel) => p.switchTo(sel.first),
                        ),
                      IconButton(
                        tooltip: 'Minuterie',
                        icon: Icon(p.sleepAt != null || p.sleepAtEndOfEpisode
                            ? Icons.bedtime_rounded
                            : Icons.bedtime_outlined),
                        color: p.sleepAt != null || p.sleepAtEndOfEpisode ? s.primary : null,
                        onPressed: () => _sleepMenu(context, p),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 20),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
    if (embedded) return page;
    return DragToDismiss(onDismiss: () => context.pop(), child: page);
  }

  Future<void> _sleepMenu(BuildContext context, PlayerController p) async {
    final choice = await showModalBottomSheet<Object>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (p.sleepAt != null)
            ListTile(
              title: Text('Arrêt à ${TimeOfDay.fromDateTime(p.sleepAt!).format(c)}'),
              leading: const Icon(Icons.bedtime),
            ),
          for (final m in const [5, 15, 30, 45, 60])
            ListTile(
              title: Text('$m minutes'),
              onTap: () => Navigator.pop(c, Duration(minutes: m)),
            ),
          ListTile(
            title: const Text("Fin de l'épisode"),
            onTap: () => Navigator.pop(c, 'end'),
          ),
          ListTile(
            title: const Text('Désactiver'),
            leading: const Icon(Icons.close),
            onTap: () => Navigator.pop(c, 'off'),
          ),
        ]),
      ),
    );
    switch (choice) {
      case Duration d:
        p.setSleepTimer(d);
      case 'end':
        p.setSleepTimer(null, endOfEpisode: true);
      case 'off':
        p.setSleepTimer(null);
    }
  }
}

class _SeekBar extends StatefulWidget {
  const _SeekBar(this.p);
  final PlayerController p;

  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final total = widget.p.duration ?? Duration.zero;
    return StreamBuilder<Duration>(
      stream: widget.p.positionStream,
      builder: (context, snap) {
        final pos = snap.data ?? widget.p.position;
        final max = total.inMilliseconds.toDouble();
        final value = (_drag ?? pos.inMilliseconds.toDouble()).clamp(0.0, max > 0 ? max : 1.0);
        final style = Theme.of(context).textTheme.bodySmall;
        return Column(children: [
          Slider(
            max: max > 0 ? max : 1,
            value: value,
            onChanged: max > 0 ? (v) => setState(() => _drag = v) : null,
            onChangeEnd: (v) {
              widget.p.seek(Duration(milliseconds: v.round()));
              setState(() => _drag = null);
            },
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(formatClock(Duration(milliseconds: value.round())), style: style),
              Text(
                  total > Duration.zero
                      ? '-${formatClock(total - Duration(milliseconds: value.round()))}'
                      : '',
                  style: style),
            ]),
          ),
        ]);
      },
    );
  }
}

/// Episodes waiting after the current one.
class QueueList extends ConsumerWidget {
  const QueueList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(playerProvider);
    if (p.queue.isEmpty) {
      return const SizedBox(
        height: 200,
        child: EmptyState(icon: Icons.queue_music, text: "La file d'attente est vide."),
      );
    }
    return ListView(shrinkWrap: true, children: [
      for (final q in p.queue)
        ListTile(
          leading: Artwork(q.episode.imageUrl ?? q.podcast.imageUrl, size: 40),
          title: Text(q.episode.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(q.podcast.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => p.removeFromQueue(q.episode.id),
          ),
          onTap: () {
            p.removeFromQueue(q.episode.id);
            p.play(q);
          },
        ),
    ]);
  }
}

class _BigPlayButton extends StatelessWidget {
  const _BigPlayButton({required this.playing, required this.buffering, required this.onPressed});
  final bool playing;
  final bool buffering;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return Container(
      width: 84,
      height: 84,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: s.primary,
        boxShadow: [
          BoxShadow(color: s.primary.withValues(alpha: 0.45), blurRadius: 28, offset: const Offset(0, 10)),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: Center(
            child: buffering
                ? SizedBox(
                    width: 32, height: 32,
                    child: CircularProgressIndicator(color: s.onPrimary, strokeWidth: 3))
                : PlayPauseIcon(playing: playing, size: 48, color: s.onPrimary),
          ),
        ),
      ),
    );
  }
}
