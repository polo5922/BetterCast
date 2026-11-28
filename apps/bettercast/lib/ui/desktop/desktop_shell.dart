import 'package:bettercast_core/bettercast_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../player/player_page.dart';
import '../../player/player_providers.dart';
import '../widgets.dart';
import 'adaptive.dart';
import 'player_bar.dart';

/// Desktop window layout: sidebar on the left, content, optional player
/// panel on the right and the player bar along the bottom.
class DesktopFrame extends ConsumerWidget {
  const DesktopFrame({
    super.key,
    required this.child,
    required this.onNavigate,
    this.selectedIndex,
  });

  final Widget child;

  /// Highlighted section, null on pages pushed above the sections.
  final int? selectedIndex;
  final ValueChanged<int> onNavigate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final panel = ref.watch(playerPanelProvider);
    final playing = ref.watch(playerProvider.select((p) => p.current != null));
    final showPanel = panel.open && playing;
    final s = Theme.of(context).colorScheme;
    // Keeps room for the content when the window is narrow.
    final maxPanel = (MediaQuery.sizeOf(context).width - 248 - 420).clamp(320.0, 760.0);

    return Scaffold(
      body: Column(children: [
        Expanded(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _Sidebar(selectedIndex: selectedIndex, onNavigate: onNavigate),
            VerticalDivider(width: 1, color: s.outlineVariant),
            Expanded(
              child: Column(children: [
                const OfflineBanner(),
                Expanded(child: child),
              ]),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (c, a) => SizeTransition(
                sizeFactor: a,
                axis: Axis.horizontal,
                axisAlignment: -1,
                child: c,
              ),
              child: showPanel
                  ? Row(key: const ValueKey('panel'), children: [
                      _ResizeHandle(
                        onDrag: (dx) =>
                            ref.read(playerPanelProvider.notifier).resize(panel.width - dx),
                      ),
                      SizedBox(
                        width: panel.width.clamp(320.0, maxPanel),
                        child: const PlayerPage(embedded: true),
                      ),
                    ])
                  : const SizedBox.shrink(key: ValueKey('none')),
            ),
          ]),
        ),
        const PlayerBar(),
      ]),
    );
  }
}

class _ResizeHandle extends StatelessWidget {
  const _ResizeHandle({required this.onDrag});
  final ValueChanged<double> onDrag;

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: (d) => onDrag(d.delta.dx),
          child: SizedBox(
            width: 7,
            child: Center(
              child: VerticalDivider(width: 1, color: Theme.of(context).colorScheme.outlineVariant),
            ),
          ),
        ),
      );
}

class _Sidebar extends ConsumerWidget {
  const _Sidebar({required this.selectedIndex, required this.onNavigate});
  final int? selectedIndex;
  final ValueChanged<int> onNavigate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final s = theme.colorScheme;
    final subs = [...?ref.watch(subscriptionsProvider).value]
      ..sort((a, b) => a.podcast.title.toLowerCase().compareTo(b.podcast.title.toLowerCase()));

    return Container(
      width: 248,
      color: s.surfaceContainerLow,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
          child: Row(children: [
            const BrandMark(size: 36),
            const SizedBox(width: 12),
            Text('BetterCast',
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Material(
            color: s.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => openSearch(GoRouter.of(context), ref),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(children: [
                  Icon(Icons.search_rounded, size: 20, color: s.onSurfaceVariant),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('Rechercher',
                        style: theme.textTheme.bodyMedium?.copyWith(color: s.onSurfaceVariant)),
                  ),
                  Text('Ctrl F',
                      style: theme.textTheme.labelSmall?.copyWith(color: s.onSurfaceVariant)),
                ]),
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        for (final (i, d) in kNavDestinations.indexed)
          _NavItem(
            icon: d.$1,
            selectedIcon: d.$2,
            label: d.$3,
            selected: i == selectedIndex,
            onTap: () => onNavigate(i),
          ),
        const SizedBox(height: 10),
        Divider(indent: 20, endIndent: 20, color: s.outlineVariant),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 8, 20, 6),
          child: Text('ABONNEMENTS',
              style: theme.textTheme.labelSmall?.copyWith(
                  letterSpacing: 1.5, fontWeight: FontWeight.w800, color: s.onSurfaceVariant)),
        ),
        Expanded(
          child: subs.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
                  child: Text('Aucun abonnement pour le moment.',
                      style: theme.textTheme.bodySmall?.copyWith(color: s.onSurfaceVariant)),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                  itemCount: subs.length,
                  itemBuilder: (_, i) => _SubscriptionItem(subs[i].podcast),
                ),
        ),
      ]),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: Material(
        color: selected ? s.secondaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Row(children: [
              Icon(selected ? selectedIcon : icon,
                  size: 22, color: selected ? s.onSecondaryContainer : s.onSurfaceVariant),
              const SizedBox(width: 14),
              Text(label,
                  style: theme.textTheme.titleSmall?.copyWith(
                      color: selected ? s.onSecondaryContainer : s.onSurface,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _SubscriptionItem extends StatelessWidget {
  const _SubscriptionItem(this.podcast);
  final Podcast podcast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = GoRouter.of(context).state.uri.path == '/podcast/${podcast.id}';
    return Material(
      color: current ? theme.colorScheme.surfaceContainerHighest : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: current ? null : () => context.push('/podcast/${podcast.id}'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(children: [
            Artwork(podcast.imageUrl, size: 34, radius: 8),
            const SizedBox(width: 10),
            Expanded(
              child: Text(podcast.title,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium),
            ),
          ]),
        ),
      ),
    );
  }
}
