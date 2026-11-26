import 'package:bettercast_core/bettercast_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../core/providers.dart';
import '../ui/widgets.dart';
import 'player_controller.dart';
import 'player_providers.dart';

class PlayerPage extends ConsumerWidget {
  const PlayerPage({super.key});

  static const _rates = [0.8, 1.0, 1.2, 1.5, 1.75, 2.0, 2.5];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(playerProvider);
    final item = p.current;
    final theme = Theme.of(context);
    if (item == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(icon: Icons.headphones, text: 'Rien en lecture'),
      );
    }
    final e = item.episode;
    final liked = ref.watch(episodeStateProvider(e.id)).liked;

    final media = p.isVideo
        ? AspectRatio(
            aspectRatio: 16 / 9,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Video(controller: p.videoController, controls: MaterialVideoControls),
            ),
          )
        : LayoutBuilder(
            builder: (_, c) => Center(
              child: Artwork(e.imageUrl ?? item.podcast.imageUrl,
                  size: c.maxWidth.clamp(120.0, 360.0), radius: 20),
            ),
          );

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down),
          onPressed: () => context.pop(),
        ),
        title: Text(item.podcast.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: "Détails de l'épisode",
            icon: const Icon(Icons.info_outline),
            onPressed: () => context.push('/episode', extra: item),
          ),
          IconButton(
            tooltip: "File d'attente",
            icon: Badge(
              isLabelVisible: p.queue.isNotEmpty,
              label: Text('${p.queue.length}'),
              child: const Icon(Icons.queue_music),
            ),
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              showDragHandle: true,
              builder: (_) => const _QueueSheet(),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(children: [
                const SizedBox(height: 8),
                Expanded(child: Center(child: media)),
                const SizedBox(height: 16),
                Text(e.title,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Wrap(spacing: 6, children: episodeBadges(e)),
                const SizedBox(height: 8),
                _SeekBar(p),
                Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                  IconButton(
                    iconSize: 32,
                    tooltip: 'Reculer de 15 s',
                    icon: const Icon(Icons.replay_10),
                    onPressed: () => p.skip(const Duration(seconds: -15)),
                  ),
                  IconButton.filled(
                    iconSize: 48,
                    tooltip: p.playing ? 'Pause' : 'Lecture',
                    icon: Icon(p.playing ? Icons.pause : Icons.play_arrow),
                    onPressed: p.playPause,
                  ),
                  IconButton(
                    iconSize: 32,
                    tooltip: 'Avancer de 30 s',
                    icon: const Icon(Icons.forward_30),
                    onPressed: () => p.skip(const Duration(seconds: 30)),
                  ),
                ]),
                const SizedBox(height: 8),
                Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                  PopupMenuButton<double>(
                    tooltip: 'Vitesse',
                    initialValue: p.rate,
                    onSelected: p.setRate,
                    itemBuilder: (_) => [
                      for (final r in _rates) PopupMenuItem(value: r, child: Text('${r}x')),
                    ],
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text('${p.rate}x', style: theme.textTheme.labelLarge),
                    ),
                  ),
                  if (e.canSwitchMedia)
                    SegmentedButton<MediaKind>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(value: MediaKind.audio, icon: Icon(Icons.headphones)),
                        ButtonSegment(value: MediaKind.video, icon: Icon(Icons.videocam)),
                      ],
                      selected: {p.isVideo ? MediaKind.video : MediaKind.audio},
                      onSelectionChanged: (s) => p.switchTo(s.first),
                    ),
                  IconButton(
                    tooltip: 'Minuterie',
                    icon: Icon(p.sleepAt != null || p.sleepAtEndOfEpisode
                        ? Icons.bedtime
                        : Icons.bedtime_outlined),
                    onPressed: () => _sleepMenu(context, p),
                  ),
                  IconButton(
                    tooltip: liked ? 'Retirer des likés' : 'Liker',
                    icon: Icon(liked ? Icons.favorite : Icons.favorite_border,
                        color: liked ? Colors.redAccent : null),
                    onPressed: () => ref.read(episodeStatesProvider.notifier).toggleLike(e),
                  ),
                ]),
                const SizedBox(height: 16),
              ]),
            ),
          ),
        ),
      ),
    );
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

class _QueueSheet extends ConsumerWidget {
  const _QueueSheet();

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
