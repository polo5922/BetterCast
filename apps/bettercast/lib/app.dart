import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';

import 'package:app_links/app_links.dart';
import 'package:bettercast_core/bettercast_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/connectivity.dart';
import 'core/notifications.dart';
import 'core/onboarding.dart';
import 'core/providers.dart';
import 'features/auth/login_page.dart';
import 'features/discover/discover_page.dart';
import 'features/discover/episode_page.dart';
import 'features/discover/podcast_page.dart';
import 'features/feed/feed_page.dart';
import 'features/library/library_page.dart';
import 'features/onboarding/onboarding_page.dart';
import 'features/patreon/patreon_page.dart';
import 'features/settings/settings_page.dart';
import 'player/mini_player.dart';
import 'player/player_page.dart';
import 'player/player_providers.dart';
import 'ui/theme.dart';
import 'ui/widgets.dart';

final _rootKey = GlobalKey<NavigatorState>();
final _messengerKey = GlobalKey<ScaffoldMessengerState>();

final routerProvider = Provider<GoRouter>((ref) {
  // Bridges the session into GoRouter's refreshListenable.
  final signedIn = ValueNotifier(ref.read(sessionProvider).signedIn);
  ref.listen(sessionProvider, (_, s) => signedIn.value = s.signedIn);
  ref.onDispose(signedIn.dispose);
  final onboarded = ValueNotifier(ref.read(onboardingDoneProvider));
  ref.listen(onboardingDoneProvider, (_, v) => onboarded.value = v);
  ref.onDispose(onboarded.dispose);

  final router = GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/feed',
    refreshListenable: Listenable.merge([signedIn, onboarded]),
    redirect: (_, state) {
      // bettercast:// links are handled by app_links (see _BetterCastAppState).
      if (state.uri.scheme == 'bettercast') return '/feed';
      final atLogin = state.matchedLocation == '/login';
      if (!signedIn.value) return atLogin ? null : '/login';
      final atOnboarding = state.matchedLocation == '/onboarding';
      if (!onboarded.value) {
        // Patreon's OAuth return may open /patreon on top of the flow.
        if (atOnboarding || state.matchedLocation == '/patreon') return null;
        return '/onboarding';
      }
      if (atLogin || atOnboarding) return '/feed';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginPage()),
      GoRoute(path: '/onboarding', builder: (_, _) => const OnboardingPage()),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => _Shell(shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: '/feed', builder: (_, _) => const FeedPage()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/discover',
              builder: (_, _) => const DiscoverPage(),
              routes: [
                GoRoute(
                  path: 'theme/:genre',
                  builder: (_, s) => ThemePage(genre: s.pathParameters['genre']!),
                ),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/library', builder: (_, _) => const LibraryPage()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/settings', builder: (_, _) => const SettingsPage()),
          ]),
        ],
      ),
      GoRoute(
        path: '/podcast/:id',
        parentNavigatorKey: _rootKey,
        builder: (_, s) => _WithMiniPlayer(PodcastPage(podcastId: s.pathParameters['id']!)),
      ),
      GoRoute(
        path: '/episode',
        parentNavigatorKey: _rootKey,
        builder: (_, s) => _WithMiniPlayer(EpisodePage(item: s.extra! as FeedItem)),
      ),
      GoRoute(
        path: '/patreon',
        parentNavigatorKey: _rootKey,
        builder: (_, _) => const _WithMiniPlayer(PatreonPage()),
      ),
      GoRoute(
        path: '/player',
        parentNavigatorKey: _rootKey,
        pageBuilder: (_, _) => const MaterialPage(fullscreenDialog: true, child: PlayerPage()),
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

class BetterCastApp extends ConsumerStatefulWidget {
  const BetterCastApp({super.key});

  @override
  ConsumerState<BetterCastApp> createState() => _BetterCastAppState();
}

class _BetterCastAppState extends ConsumerState<BetterCastApp> {
  final _subs = <StreamSubscription<Object?>>[];

  @override
  void initState() {
    super.initState();
    final router = ref.read(routerProvider);
    // Player messages (e.g. offline) as snack bars.
    _subs.add(ref.read(playerProvider).messages.listen((m) {
      _messengerKey.currentState
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(m)));
    }));
    // Media notification tap -> full player.
    if (Platform.isAndroid) {
      _subs.add(AudioService.notificationClicked.where((c) => c).listen((_) {
        if (ref.read(playerProvider).current == null) return;
        final at = router.routerDelegate.currentConfiguration.uri.path;
        if (at != '/player') router.push('/player');
      }));
    }
    // Notification tap -> podcast page.
    _subs.add(ref.read(notificationsProvider).taps.listen((podcastId) {
      router.push('/podcast/$podcastId');
    }));
    // bettercast://patreon/connected?status=ok (OAuth return on Android).
    _subs.add(AppLinks().uriLinkStream.listen((uri) {
      if (uri.scheme != 'bettercast' || uri.host != 'patreon') return;
      ref.read(sessionProvider.notifier).refreshProfile();
      ref.invalidate(patreonCampaignsProvider);
      if (uri.queryParameters['status'] == 'error') {
        final c = _rootKey.currentContext;
        if (c != null && c.mounted) {
          ScaffoldMessenger.of(c).showSnackBar(
              const SnackBar(content: Text('La connexion à Patreon a échoué')));
        }
      }
      router.push('/patreon');
    }, onError: (_) {}));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'BetterCast',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: _messengerKey,
      theme: ref.watch(brandThemeProvider(Brightness.light)),
      darkTheme: ref.watch(brandThemeProvider(Brightness.dark)),
      routerConfig: ref.watch(routerProvider),
    );
  }
}

/// Adaptive shell: bottom navigation on phones, side rail on wide windows.
class _Shell extends ConsumerWidget {
  const _Shell(this.shell);
  final StatefulNavigationShell shell;

  static const _dest = [
    (Icons.auto_awesome_outlined, Icons.auto_awesome, 'Nouveautés'),
    (Icons.explore_outlined, Icons.explore, 'Découvrir'),
    (Icons.library_music_outlined, Icons.library_music, 'Bibliothèque'),
    (Icons.tune_outlined, Icons.tune, 'Réglages'),
  ];

  void _go(int i) => shell.goBranch(i, initialLocation: i == shell.currentIndex);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wide = MediaQuery.sizeOf(context).width >= 840;
    if (wide) {
      return Scaffold(
        body: Row(children: [
          NavigationRail(
            selectedIndex: shell.currentIndex,
            onDestinationSelected: _go,
            labelType: NavigationRailLabelType.all,
            leading: const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: BrandMark(size: 44),
            ),
            destinations: [
              for (final d in _dest)
                NavigationRailDestination(
                    icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: Text(d.$3)),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(
              child: Column(children: [
            const OfflineBanner(),
            Expanded(child: shell),
            const MiniPlayer(),
          ])),
        ]),
      );
    }
    return Scaffold(
      body: Column(children: [
        const SafeArea(bottom: false, child: OfflineBanner()),
        Expanded(child: MediaQuery.removePadding(
          context: context,
          removeTop: ref.watch(onlineProvider) == false,
          child: shell,
        )),
      ]),
      bottomNavigationBar: Column(mainAxisSize: MainAxisSize.min, children: [
        const MiniPlayer(),
        NavigationBar(
          selectedIndex: shell.currentIndex,
          onDestinationSelected: _go,
          destinations: [
            for (final d in _dest)
              NavigationDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: d.$3),
          ],
        ),
      ]),
    );
  }
}

/// Pushed pages outside the shell still show the mini player.
class _WithMiniPlayer extends StatelessWidget {
  const _WithMiniPlayer(this.child);
  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
        color: Theme.of(context).colorScheme.surface,
        child: Column(children: [
          Expanded(child: child),
          const SafeArea(top: false, child: MiniPlayer()),
        ]),
      );
}
