import 'package:bettercast_core/bettercast_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auto_downloads.dart';
import 'widgets.dart';

String autoDownloadLabel(int n) => switch (n) {
      0 => 'Désactivé',
      1 => 'Le dernier',
      _ => 'Les $n derniers',
    };

/// Lets the user pick how many of a show's latest episodes stay downloaded.
Future<void> showAutoDownloadSheet(BuildContext context, Podcast podcast) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AutoDownloadSheet(podcast),
    );

class _AutoDownloadSheet extends ConsumerStatefulWidget {
  const _AutoDownloadSheet(this.podcast);
  final Podcast podcast;

  @override
  ConsumerState<_AutoDownloadSheet> createState() => _AutoDownloadSheetState();
}

class _AutoDownloadSheetState extends ConsumerState<_AutoDownloadSheet> {
  @override
  Widget build(BuildContext context) {
    final p = widget.podcast;
    final current = ref.watch(autoDownloadsProvider.select((m) => m[p.id] ?? 0));
    final notifier = ref.read(autoDownloadsProvider.notifier);
    final theme = Theme.of(context);
    final s = theme.colorScheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Artwork(p.imageUrl, size: 52, radius: 14),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Téléchargement auto', style: theme.textTheme.titleLarge),
                Text(p.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(color: s.onSurfaceVariant)),
              ]),
            ),
          ]),
          const SizedBox(height: 20),
          Text('Combien d’épisodes récents garder sur cet appareil ?',
              style: theme.textTheme.bodyMedium),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final n in kAutoDownloadChoices)
              ChoiceChip(
                label: Text(n == 0 ? 'Off' : '$n'),
                avatar: n == 0 ? const Icon(Icons.block_rounded, size: 18) : null,
                selected: current == n,
                onSelected: (_) => notifier.set(p.id, n),
              ),
          ]),
          const SizedBox(height: 16),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Container(
              key: ValueKey(current),
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: s.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(children: [
                Icon(current > 0 ? Icons.download_for_offline_rounded : Icons.cloud_outlined,
                    color: s.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(switch (current) {
                    0 => 'Rien n’est téléchargé automatiquement.',
                    1 => 'Le dernier épisode sera toujours prêt hors ligne. L’ancien est supprimé quand un nouveau sort.',
                    _ => 'Les $current derniers épisodes seront toujours prêts hors ligne. Les plus anciens sont supprimés au fur et à mesure.',
                  }),
                ),
              ]),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Uniquement en Wi-Fi'),
            subtitle: const Text('Pour tous les podcasts'),
            value: notifier.wifiOnly,
            onChanged: (v) => setState(() => notifier.wifiOnly = v),
          ),
        ]),
      ),
    );
  }
}
