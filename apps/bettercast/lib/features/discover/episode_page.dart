import 'package:bettercast_core/bettercast_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/downloads.dart';
import '../../core/local_db.dart';
import '../../core/providers.dart';
import '../../player/player_providers.dart';
import '../../ui/widgets.dart';

class EpisodePage extends ConsumerWidget {
  const EpisodePage({super.key, required this.item});
  final FeedItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = item.episode;
    final p = item.podcast;
    final state = ref.watch(episodeStateProvider(e.id));
    final download = ref.watch(downloadsProvider.select((m) => m[e.id]));
    final player = ref.read(playerProvider);
    final theme = Theme.of(context);
    final states = ref.read(episodeStatesProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: Text(p.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Voir le podcast',
            icon: const Icon(Icons.podcasts),
            onPressed: () => context.push('/podcast/${p.id}'),
          ),
          if (e.link != null)
            IconButton(
              tooltip: 'Ouvrir la page web',
              icon: const Icon(Icons.open_in_new),
              onPressed: () => launchUrl(Uri.parse(e.link!)),
            ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Artwork(e.imageUrl ?? p.imageUrl, size: 96, radius: 12),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e.title, style: theme.textTheme.titleLarge),
              const SizedBox(height: 6),
              Text(
                [
                  formatDate(e.publishedAt),
                  formatDuration(e.duration),
                  if (e.season != null) 'Saison ${e.season}',
                  if (e.number != null) 'Épisode ${e.number}',
                ].where((s) => s.isNotEmpty).join(' · '),
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 4, children: [
                ...episodeBadges(e),
                if (e.explicit) const Badge2('Explicite'),
                if (e.transcripts.isNotEmpty) const Badge2('Transcription', icon: Icons.subtitles),
              ]),
            ]),
          ),
        ]),
        const SizedBox(height: 16),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.icon(
            onPressed: () => player.play(item, kind: e.hasAudio ? MediaKind.audio : null),
            icon: const Icon(Icons.play_arrow),
            label: Text(state.inProgress ? 'Reprendre ${formatClock(state.position)}' : 'Écouter'),
          ),
          if (e.hasVideo)
            FilledButton.tonalIcon(
              onPressed: () {
                player.play(item, kind: MediaKind.video);
                context.push('/player');
              },
              icon: const Icon(Icons.videocam),
              label: const Text('Regarder'),
            ),
          OutlinedButton.icon(
            onPressed: () {
              player.enqueue(item);
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('Ajouté à la file')));
            },
            icon: const Icon(Icons.queue_music),
            label: const Text('File'),
          ),
          IconButton.outlined(
            tooltip: state.liked ? 'Retirer des likés' : 'Liker',
            onPressed: () => states.toggleLike(e),
            icon: Icon(state.liked ? Icons.favorite : Icons.favorite_border,
                color: state.liked ? Colors.redAccent : null),
          ),
          IconButton.outlined(
            tooltip: state.played ? 'Marquer non écouté' : 'Marquer écouté',
            onPressed: () => states.setPlayed(e, !state.played),
            icon: Icon(state.played ? Icons.check_circle : Icons.check_circle_outline),
          ),
          _DownloadButton(item: item, download: download),
        ]),
        const Divider(height: 32),
        if (e.description.isNotEmpty)
          SelectionArea(
            child: HtmlWidget(
              e.description,
              textStyle: theme.textTheme.bodyMedium,
              onTapUrl: (url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
            ),
          )
        else
          Text(e.summary ?? 'Pas de description.'),
      ]),
    );
  }
}

class _DownloadButton extends ConsumerWidget {
  const _DownloadButton({required this.item, required this.download});
  final FeedItem item;
  final DownloadRecord? download;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = ref.read(downloadsProvider.notifier);
    final d = download;
    if (d == null || d.status == 'failed') {
      return IconButton.outlined(
        tooltip: d == null ? 'Télécharger' : 'Réessayer le téléchargement',
        icon: Icon(d == null ? Icons.download : Icons.refresh),
        onPressed: () => n.download(item),
      );
    }
    if (!d.isComplete) {
      return IconButton.outlined(
        tooltip: 'Annuler',
        onPressed: () => n.remove(item.episode.id),
        icon: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(value: d.progress > 0 ? d.progress : null, strokeWidth: 2),
        ),
      );
    }
    return IconButton.outlined(
      tooltip: 'Supprimer le téléchargement',
      icon: const Icon(Icons.download_done),
      onPressed: () => n.remove(item.episode.id),
    );
  }
}
