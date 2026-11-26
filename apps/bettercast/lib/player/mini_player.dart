import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'player_providers.dart';

/// Floating card shown above the navigation bar while something plays,
/// tinted with the colors of the current cover.
class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = ref.watch(playerProvider.select((p) => p.current));
    if (item == null) return const SizedBox.shrink();
    final cover = item.episode.imageUrl ?? item.podcast.imageUrl;
    return ArtworkTheme(artworkUrl: cover, child: const _MiniPlayerCard());
  }
}

class _MiniPlayerCard extends ConsumerWidget {
  const _MiniPlayerCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(playerProvider);
    final item = p.current!;
    final theme = Theme.of(context);
    final s = theme.colorScheme;
    final total = p.duration?.inMilliseconds ?? 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      child: Material(
        color: Color.alphaBlend(s.primary.withValues(alpha: 0.22), s.surfaceContainerHigh),
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        elevation: 6,
        shadowColor: Colors.black54,
        child: InkWell(
          onTap: () => context.push('/player'),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 6, 6),
              child: Row(children: [
                Artwork(item.episode.imageUrl ?? item.podcast.imageUrl, size: 46, radius: 14),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(item.episode.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall),
                    Text(item.podcast.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(color: s.primary)),
                  ]),
                ),
                if (item.episode.canSwitchMedia)
                  IconButton(
                    tooltip: p.isVideo ? 'Passer en audio' : 'Passer en vidéo',
                    icon: Icon(p.isVideo ? Icons.headphones_rounded : Icons.videocam_rounded),
                    onPressed: p.toggleMediaKind,
                  ),
                IconButton(
                  tooltip: 'Reculer de 15 s',
                  icon: const Icon(Icons.replay_10_rounded),
                  onPressed: () => p.skip(const Duration(seconds: -15)),
                ),
                SizedBox(
                  width: 44,
                  height: 44,
                  child: p.buffering
                      ? const Padding(
                          padding: EdgeInsets.all(10),
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        )
                      : IconButton.filled(
                          tooltip: p.playing ? 'Pause' : 'Lecture',
                          icon: Icon(p.playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                          onPressed: p.playPause,
                        ),
                ),
              ]),
            ),
            StreamBuilder<Duration>(
              stream: p.positionStream,
              builder: (_, snap) => Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
                child: LinearProgressIndicator(
                  minHeight: 3,
                  value: total > 0
                      ? ((snap.data ?? p.position).inMilliseconds / total).clamp(0.0, 1.0)
                      : 0,
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
