import 'dart:async';
import 'dart:io';

import 'package:bettercast_core/bettercast_core.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auto_downloads.dart';
import '../../core/notifications.dart';
import '../../core/onboarding.dart';
import '../../core/providers.dart';
import '../../ui/widgets.dart';
import '../discover/themes.dart';

/// First-run flow: presentation, permissions (Android), first
/// subscriptions and optional Patreon connection.
class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  final _pages = PageController();
  int _index = 0;

  late final List<Widget> _steps = [
    const _Welcome(),
    if (Platform.isAndroid) const _Permissions(),
    const _FirstSubscriptions(),
    const _Patreon(),
  ];

  bool get _last => _index == _steps.length - 1;

  void _finish() => ref.read(onboardingDoneProvider.notifier).complete();

  void _next() {
    if (_last) return _finish();
    unawaited(_pages.nextPage(
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
    ));
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(children: [
              Align(
                alignment: Alignment.centerRight,
                child: AnimatedOpacity(
                  opacity: _last ? 0 : 1,
                  duration: const Duration(milliseconds: 200),
                  child: TextButton(onPressed: _last ? null : _finish, child: const Text('Passer')),
                ),
              ),
              Expanded(
                child: PageView(
                  controller: _pages,
                  onPageChanged: (i) => setState(() => _index = i),
                  children: _steps,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                child: Row(children: [
                  for (var i = 0; i < _steps.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOut,
                      margin: const EdgeInsets.only(right: 6),
                      width: i == _index ? 22 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: i == _index ? cs.primary : cs.outlineVariant,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _next,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: Text(_last ? 'Commencer' : 'Suivant', key: ValueKey(_last)),
                    ),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Common layout: icon/illustration, title, text, then the step content.
class _Step extends StatelessWidget {
  const _Step({required this.top, required this.title, this.text, this.child});
  final Widget top;
  final String title;
  final String? text;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      children: [
        const SizedBox(height: 12),
        Center(child: top),
        const SizedBox(height: 24),
        Text(title, style: t.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
        if (text != null) ...[
          const SizedBox(height: 8),
          Text(text!, style: t.bodyLarge?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
        if (child != null) ...[const SizedBox(height: 20), child!],
      ],
    );
  }
}

class _Feature extends StatelessWidget {
  const _Feature(this.icon, this.title, this.text);
  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: cs.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: cs.onPrimaryContainer),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            Text(text, style: TextStyle(color: cs.onSurfaceVariant)),
          ]),
        ),
      ]),
    );
  }
}

class _Welcome extends ConsumerWidget {
  const _Welcome();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = ref.watch(sessionProvider).user?.displayName;
    return _Step(
      top: const BrandMark(size: 96),
      title: name == null ? 'Bienvenue sur BetterCast' : 'Bienvenue, $name',
      text: 'Tous tes podcasts au même endroit, synchronisés entre ton téléphone, '
          'ta voiture et ton PC.',
      child: const Column(children: [
        _Feature(Icons.podcasts, 'Podcasts publics et Patreon',
            'Les flux réservés aux membres arrivent avec les autres.'),
        _Feature(Icons.ondemand_video_outlined, 'Audio ou vidéo',
            'Passe de l’un à l’autre sans perdre ta position.'),
        _Feature(Icons.offline_pin_outlined, 'Hors ligne',
            'Les épisodes téléchargés se lisent sans réseau, la position se synchronise au retour.'),
        _Feature(Icons.directions_car_outlined, 'Android Auto',
            'Reprends ton écoute en un geste depuis la voiture.'),
      ]),
    );
  }
}

class _Permissions extends ConsumerStatefulWidget {
  const _Permissions();

  @override
  ConsumerState<_Permissions> createState() => _PermissionsState();
}

class _PermissionsState extends ConsumerState<_Permissions> {
  bool? _notifications;

  Future<void> _askNotifications() async {
    final ok = await ref.read(notificationsProvider).requestPermission();
    if (mounted) setState(() => _notifications = ok);
  }

  @override
  Widget build(BuildContext context) {
    final auto = ref.read(autoDownloadsProvider.notifier);
    return _Step(
      top: Icon(Icons.notifications_active_outlined,
          size: 88, color: Theme.of(context).colorScheme.primary),
      title: 'Reste à jour',
      text: 'BetterCast te prévient à la sortie d’un nouvel épisode et affiche '
          'le lecteur dans tes notifications.',
      child: Column(children: [
        Card.outlined(
          child: ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('Notifications'),
            subtitle: Text(switch (_notifications) {
              true => 'Autorisées',
              false => 'Refusées : tu pourras les activer dans les réglages Android',
              null => 'Nouveaux épisodes et lecteur',
            }),
            trailing: _notifications == true
                ? const Icon(Icons.check_circle, color: Colors.green)
                : FilledButton.tonal(onPressed: _askNotifications, child: const Text('Autoriser')),
          ),
        ),
        const SizedBox(height: 8),
        Card.outlined(
          child: SwitchListTile(
            secondary: const Icon(Icons.wifi),
            title: const Text('Téléchargements auto en Wi-Fi uniquement'),
            subtitle: const Text('Pour ne pas consommer ton forfait'),
            value: auto.wifiOnly,
            onChanged: (v) => setState(() => auto.wifiOnly = v),
          ),
        ),
      ]),
    );
  }
}

class _FirstSubscriptions extends ConsumerStatefulWidget {
  const _FirstSubscriptions();

  @override
  ConsumerState<_FirstSubscriptions> createState() => _FirstSubscriptionsState();
}

class _FirstSubscriptionsState extends ConsumerState<_FirstSubscriptions> {
  String? _genre;
  final _busy = <String>{};
  bool _importing = false;

  Future<void> _toggle(SearchResult r, bool subscribed) async {
    setState(() => _busy.add(r.feedUrl));
    final api = ref.read(apiProvider);
    try {
      if (subscribed) {
        await api.unsubscribe(r.podcastId);
      } else {
        final d = await api.lookup(r.feedUrl);
        await api.subscribe(d.podcast.id);
      }
      ref.invalidate(subscriptionsProvider);
      ref.invalidate(newReleasesProvider);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy.remove(r.feedUrl));
    }
  }

  Future<void> _importOpml() async {
    setState(() => _importing = true);
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['opml', 'xml'],
      );
      if (files.isEmpty) return;
      final r = await ref.read(apiProvider).importOpml(await files.first.xFile.readAsString());
      ref.invalidate(subscriptionsProvider);
      ref.invalidate(newReleasesProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('${r.imported} podcasts importés'
                '${r.failed.isEmpty ? '' : ', ${r.failed.length} en échec'}')));
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final subscribed = ref.watch(subscribedIdsProvider);
    final top = ref.watch(trendingProvider(_genre));
    return _Step(
      top: Icon(Icons.library_add_outlined, size: 88, color: Theme.of(context).colorScheme.primary),
      title: 'Tes premiers podcasts',
      text: subscribed.isEmpty
          ? 'Choisis un thème et abonne-toi en un tap, ou importe tes abonnements.'
          : '${subscribed.length} abonnement${subscribed.length > 1 ? 's' : ''}. '
              'Tu pourras en ajouter d’autres dans Découvrir.',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        OutlinedButton.icon(
          onPressed: _importing ? null : _importOpml,
          icon: _importing
              ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.file_upload_outlined),
          label: const Text('Importer depuis une autre app (OPML)'),
        ),
        const SizedBox(height: 16),
        // One scrollable row of themes so the podcasts stay in view.
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          child: Row(spacing: 8, children: [
          ChoiceChip(
            label: const Text('Populaires'),
            selected: _genre == null,
            onSelected: (_) => setState(() => _genre = null),
          ),
          for (final t in PodcastTheme.all)
            ChoiceChip(
              avatar: Icon(t.icon, size: 18, color: t.color),
              label: Text(t.label),
              selected: _genre == t.genre,
              onSelected: (_) => setState(() => _genre = t.genre),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: top.when(
            loading: () => const Padding(
              key: ValueKey('loading'),
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Padding(
              key: const ValueKey('error'),
              padding: const EdgeInsets.all(16),
              child: Text('Impossible de charger les podcasts populaires.',
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
            data: (list) => Column(
              key: ValueKey(_genre),
              children: [
                for (final r in list.take(15))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Artwork(r.imageUrl),
                    title: Text(r.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: r.author == null
                        ? null
                        : Text(r.author!, maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: _SubscribeButton(
                      subscribed: subscribed.contains(r.podcastId),
                      busy: _busy.contains(r.feedUrl),
                      onPressed: () => _toggle(r, subscribed.contains(r.podcastId)),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ]),
    );
  }
}

class _SubscribeButton extends StatelessWidget {
  const _SubscribeButton({required this.subscribed, required this.busy, required this.onPressed});
  final bool subscribed;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    if (busy) {
      return const SizedBox.square(
          dimension: 40, child: Padding(padding: EdgeInsets.all(10), child: CircularProgressIndicator(strokeWidth: 2)));
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
      child: subscribed
          ? IconButton.filled(
              key: const ValueKey(true),
              tooltip: 'Se désabonner',
              onPressed: onPressed,
              icon: const Icon(Icons.check),
            )
          : IconButton.outlined(
              key: const ValueKey(false),
              tooltip: 'S’abonner',
              onPressed: onPressed,
              icon: const Icon(Icons.add),
            ),
    );
  }
}

class _Patreon extends ConsumerWidget {
  const _Patreon();

  Future<void> _connect(BuildContext context, WidgetRef ref) async {
    try {
      final url = await ref.read(apiProvider).patreonAuthorizeUrl();
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connected = ref.watch(sessionProvider).user?.patreonConnected == true;
    return _Step(
      top: const Icon(Icons.star_rounded, size: 96, color: premiumColor),
      title: 'Tu soutiens des créateurs sur Patreon ?',
      text: 'Connecte ton compte pour retrouver les épisodes réservés aux membres '
          'dans ton fil, avec le reste. Tu peux aussi le faire plus tard dans les Réglages.',
      child: connected
          ? const Card.outlined(
              child: ListTile(
                leading: Icon(Icons.check_circle, color: Colors.green),
                title: Text('Patreon est connecté'),
              ),
            )
          : FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: premiumColor, foregroundColor: Colors.black),
              onPressed: () => _connect(context, ref),
              icon: const Icon(Icons.link),
              label: const Text('Connecter Patreon'),
            ),
    );
  }
}
