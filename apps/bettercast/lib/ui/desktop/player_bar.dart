import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../player/player_controller.dart';
import '../../player/player_page.dart';
import '../../player/player_providers.dart';
import '../theme.dart';
import '../widgets.dart';
import 'adaptive.dart';

/// Full-width transport bar at the bottom of the desktop window.
class PlayerBar extends ConsumerWidget {
  const PlayerBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = ref.watch(playerProvider.select((p) => p.current));
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: item == null
          ? const SizedBox(width: double.infinity)
          : ArtworkTheme(
              artworkUrl: item.episode.imageUrl ?? item.podcast.imageUrl,
              child: const _Bar(),
            ),
    );
  }
}

class _Bar extends ConsumerWidget {
  const _Bar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(playerProvider);
    final panelOpen = ref.watch(playerPanelProvider.select((s) => s.open));
    final item = p.current!;
    final e = item.episode;
    final theme = Theme.of(context);
    final s = theme.colorScheme;

    return Material(
      color: Color.alphaBlend(s.primary.withValues(alpha: 0.12), s.surfaceContainer),
      child: Container(
        height: 100,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(border: Border(top: BorderSide(color: s.outlineVariant))),
        child: Row(children: [
          // Now playing: opens the side panel.
          Expanded(
            flex: 3,
            child: Align(
              alignment: Alignment.centerLeft,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => ref.read(playerPanelProvider.notifier).toggle(),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Artwork(e.imageUrl ?? item.podcast.imageUrl, size: 60, radius: 12, shadow: true),
                    const SizedBox(width: 14),
                    Flexible(
                      child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(e.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall),
                            Text(item.podcast.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(color: s.primary, fontWeight: FontWeight.w700)),
                          ]),
                    ),
                  ]),
                ),
              ),
            ),
          ),
          // Transport and progress.
          Expanded(
            flex: 4,
            child: Column(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                IconButton(
                  tooltip: 'Reculer de 15 s (←)',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.replay_rounded),
                  onPressed: () => p.skip(const Duration(seconds: -15)),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 44,
                  height: 44,
                  child: p.buffering || p.loading
                      ? const Padding(
                          padding: EdgeInsets.all(10),
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        )
                      : IconButton.filled(
                          tooltip: p.playing ? 'Pause (Espace)' : 'Lecture (Espace)',
                          icon: Icon(p.playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                          onPressed: p.playPause,
                        ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Avancer de 30 s (→)',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.forward_30_rounded),
                  onPressed: () => p.skip(const Duration(seconds: 30)),
                ),
                if (p.queue.isNotEmpty)
                  IconButton(
                    tooltip: 'Épisode suivant',
                  visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.skip_next_rounded),
                    onPressed: p.skipToNext,
                  ),
              ]),
              _InlineSeek(p),
            ]),
          ),
          // Speed, media kind, volume, queue, panel.
          Expanded(
            flex: 3,
            child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              PopupMenuButton<double>(
                tooltip: 'Vitesse',
                initialValue: p.rate,
                onSelected: p.setRate,
                itemBuilder: (_) => [
                  for (final r in PlayerPage.rates) PopupMenuItem(value: r, child: Text('${r}x')),
                ],
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Text('${p.rate}x', style: theme.textTheme.labelLarge),
                ),
              ),
              if (e.canSwitchMedia)
                IconButton(
                  tooltip: p.isVideo ? 'Passer en audio' : 'Passer en vidéo',
                  icon: Icon(p.isVideo ? Icons.headphones_rounded : Icons.videocam_rounded),
                  onPressed: p.toggleMediaKind,
                ),
              IconButton(
                tooltip: "File d'attente",
                icon: Badge(
                  isLabelVisible: p.queue.isNotEmpty,
                  label: Text('${p.queue.length}'),
                  child: const Icon(Icons.queue_music_rounded),
                ),
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: const Text("File d'attente"),
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    content: const SizedBox(width: 460, child: QueueList()),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(c), child: const Text('Fermer')),
                    ],
                  ),
                ),
              ),
              Flexible(child: _Volume(p)),
              IconButton(
                tooltip: panelOpen ? 'Fermer le lecteur' : 'Ouvrir le lecteur',
                isSelected: panelOpen,
                icon: const Icon(Icons.view_sidebar_outlined),
                selectedIcon: const Icon(Icons.view_sidebar_rounded),
                onPressed: () => ref.read(playerPanelProvider.notifier).toggle(),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _InlineSeek extends StatefulWidget {
  const _InlineSeek(this.p);
  final PlayerController p;

  @override
  State<_InlineSeek> createState() => _InlineSeekState();
}

class _InlineSeekState extends State<_InlineSeek> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final total = widget.p.duration ?? Duration.zero;
    final style = Theme.of(context).textTheme.labelSmall;
    return StreamBuilder<Duration>(
      stream: widget.p.positionStream,
      builder: (context, snap) {
        final pos = snap.data ?? widget.p.position;
        final max = total.inMilliseconds.toDouble();
        final value = (_drag ?? pos.inMilliseconds.toDouble()).clamp(0.0, max > 0 ? max : 1.0);
        return Row(children: [
          SizedBox(
            width: 56,
            child: Text(formatClock(Duration(milliseconds: value.round())),
                textAlign: TextAlign.right, style: style),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              ),
              child: Slider(
                max: max > 0 ? max : 1,
                value: value,
                onChanged: max > 0 ? (v) => setState(() => _drag = v) : null,
                onChangeEnd: (v) {
                  widget.p.seek(Duration(milliseconds: v.round()));
                  setState(() => _drag = null);
                },
              ),
            ),
          ),
          SizedBox(
            width: 56,
            child: Text(total > Duration.zero ? formatClock(total) : '', style: style),
          ),
        ]);
      },
    );
  }
}

class _Volume extends StatefulWidget {
  const _Volume(this.p);
  final PlayerController p;

  @override
  State<_Volume> createState() => _VolumeState();
}

class _VolumeState extends State<_Volume> {
  double _beforeMute = 100;

  @override
  Widget build(BuildContext context) {
    final player = widget.p.player;
    return StreamBuilder<double>(
      stream: player.stream.volume,
      initialData: player.state.volume,
      builder: (context, snap) {
        final v = (snap.data ?? 100).clamp(0.0, 100.0);
        return Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
            tooltip: v == 0 ? 'Rétablir le son' : 'Couper le son',
            icon: Icon(v == 0
                ? Icons.volume_off_rounded
                : v < 50
                    ? Icons.volume_down_rounded
                    : Icons.volume_up_rounded),
            onPressed: () {
              if (v == 0) {
                player.setVolume(_beforeMute);
              } else {
                _beforeMute = v;
                player.setVolume(0);
              }
            },
          ),
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 110),
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                ),
                child: Slider(max: 100, value: v, onChanged: player.setVolume),
              ),
            ),
          ),
        ]);
      },
    );
  }
}
