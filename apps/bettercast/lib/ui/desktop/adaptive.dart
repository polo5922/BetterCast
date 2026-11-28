import 'package:bettercast_core/bettercast_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../motion.dart';
import '../widgets.dart';

/// Window width from which the desktop layout (sidebar + player bar) is used.
const kDesktopBreakpoint = 840.0;

bool isWideLayout(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= kDesktopBreakpoint;

/// Main sections, shared by the phone navigation bar and the desktop sidebar.
const kNavDestinations = [
  (Icons.auto_awesome_outlined, Icons.auto_awesome, 'Nouveautés', '/feed'),
  (Icons.explore_outlined, Icons.explore, 'Découvrir', '/discover'),
  (Icons.library_music_outlined, Icons.library_music, 'Bibliothèque', '/library'),
  (Icons.tune_outlined, Icons.tune, 'Réglages', '/settings'),
];

/// Focus of the search bar of the Discover page (Ctrl+F, sidebar search).
final searchFocusProvider = Provider<FocusNode>((ref) {
  final node = FocusNode(debugLabel: 'search');
  ref.onDispose(node.dispose);
  return node;
});

/// Opens Discover with the search bar focused.
void openSearch(GoRouter router, WidgetRef ref) {
  router.go('/discover');
  WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(searchFocusProvider).requestFocus());
}

/// State of the desktop player side panel.
class PlayerPanelNotifier extends Notifier<({bool open, double width})> {
  @override
  ({bool open, double width}) build() => (open: false, width: 400);

  void show() => state = (open: true, width: state.width);
  void hide() => state = (open: false, width: state.width);
  void toggle() => state = (open: !state.open, width: state.width);
  void resize(double width) => state = (open: state.open, width: width.clamp(320.0, 760.0));
}

final playerPanelProvider =
    NotifierProvider<PlayerPanelNotifier, ({bool open, double width})>(PlayerPanelNotifier.new);

/// Full player: side panel on desktop, full-screen page on phones.
void openPlayer(BuildContext context, WidgetRef ref) {
  if (isWideLayout(context)) {
    ref.read(playerPanelProvider.notifier).show();
  } else {
    context.push('/player');
  }
}

/// [itemCount] tiles as a list on narrow widths, in columns of at least
/// [minTileWidth] otherwise (rows keep the tiles' natural height).
Widget adaptiveColumns({
  required int itemCount,
  required IndexedWidgetBuilder itemBuilder,
  double minTileWidth = 460,
}) =>
    StaggerScope(child: SliverLayoutBuilder(builder: (context, c) {
      final cols = (c.crossAxisExtent / minTileWidth).floor().clamp(1, 3);
      Widget item(BuildContext context, int i) => Stagger(index: i, child: itemBuilder(context, i));
      if (cols == 1) return SliverList.builder(itemCount: itemCount, itemBuilder: item);
      final rows = (itemCount / cols).ceil();
      return SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        sliver: SliverList.builder(
          itemCount: rows,
          itemBuilder: (context, r) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (var k = 0; k < cols; k++)
              Expanded(
                child: r * cols + k < itemCount
                    ? item(context, r * cols + k)
                    : const SizedBox.shrink(),
              ),
          ]),
        ),
      );
    }));

/// Episodes as a list on phones, in columns on wide windows.
Widget adaptiveEpisodes(List<FeedItem> items, {bool showPodcast = true}) => adaptiveColumns(
      itemCount: items.length,
      itemBuilder: (_, i) => EpisodeTile(items[i], showPodcast: showPodcast),
    );
