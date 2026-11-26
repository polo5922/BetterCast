import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../ui/widgets.dart';
import 'player_providers.dart';

/// Persistent strip shown above the navigation bar while something plays.
class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(playerProvider);
    final item = p.current;
    if (item == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final total = p.duration?.inMilliseconds ?? 0;

    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      child: InkWell(
        onTap: () => context.push('/player'),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          StreamBuilder<Duration>(
            stream: p.positionStream,
            builder: (_, s) => LinearProgressIndicator(
              minHeight: 2,
              value: total > 0
                  ? ((s.data ?? p.position).inMilliseconds / total).clamp(0.0, 1.0)
                  : 0,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
            child: Row(children: [
              Artwork(item.episode.imageUrl ?? item.podcast.imageUrl, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(item.episode.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium),
                  Text(item.podcast.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
                ]),
              ),
              if (item.episode.canSwitchMedia)
                IconButton(
                  tooltip: p.isVideo ? 'Passer en audio' : 'Passer en vidéo',
                  icon: Icon(p.isVideo ? Icons.headphones : Icons.videocam),
                  onPressed: p.toggleMediaKind,
                ),
              IconButton(
                tooltip: 'Reculer de 15 s',
                icon: const Icon(Icons.replay_10),
                onPressed: () => p.skip(const Duration(seconds: -15)),
              ),
              IconButton(
                tooltip: p.playing ? 'Pause' : 'Lecture',
                icon: p.buffering
                    ? const SizedBox(
                        width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(p.playing ? Icons.pause : Icons.play_arrow),
                onPressed: p.playPause,
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
