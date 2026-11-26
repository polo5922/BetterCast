import 'dart:async';

import 'package:bettercast_core/bettercast_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/providers.dart';
import '../../ui/widgets.dart';

/// Connect Patreon, list supported creators, attach each one's private RSS.
class PatreonPage extends ConsumerStatefulWidget {
  const PatreonPage({super.key});

  @override
  ConsumerState<PatreonPage> createState() => _PatreonPageState();
}

class _PatreonPageState extends ConsumerState<PatreonPage> with WidgetsBindingObserver {
  bool _waitingForOAuth = false;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Coming back from the browser (Windows, or Android without deep link):
  /// re-check the connection.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _waitingForOAuth) {
      _waitingForOAuth = false;
      _refreshAll();
    }
  }

  Future<void> _refreshAll() async {
    await ref.read(sessionProvider.notifier).refreshProfile();
    ref.invalidate(patreonCampaignsProvider);
  }

  Future<void> _connect() async {
    try {
      final url = await ref.read(apiProvider).patreonAuthorizeUrl();
      _waitingForOAuth = true;
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _sync() async {
    setState(() => _syncing = true);
    try {
      await ref.read(apiProvider).patreonCampaigns(sync: true);
      ref.invalidate(patreonCampaignsProvider);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _disconnect() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Déconnecter Patreon ?'),
        content: const Text(
            'Les flux privés déjà associés restent dans tes abonnements, mais la liste des créateurs ne sera plus mise à jour.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Déconnecter')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(apiProvider).disconnectPatreon();
      await _refreshAll();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _link(PatreonCampaign c) async {
    final url = await showDialog<String>(context: context, builder: (_) => _LinkFeedDialog(c));
    if (url == null || url.isEmpty) return;
    try {
      final d = await ref.read(apiProvider).linkPatreonFeed(c.id, url);
      ref.invalidate(patreonCampaignsProvider);
      ref.invalidate(subscriptionsProvider);
      ref.invalidate(newReleasesProvider);
      if (mounted) context.push('/podcast/${d.podcast.id}');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final connected = ref.watch(sessionProvider.select((s) => s.user?.patreonConnected ?? false));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Patreon'),
        actions: [
          if (connected) ...[
            IconButton(
              tooltip: 'Synchroniser',
              onPressed: _syncing ? null : _sync,
              icon: _syncing
                  ? const SizedBox(
                      width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.sync),
            ),
            IconButton(
                tooltip: 'Déconnecter', onPressed: _disconnect, icon: const Icon(Icons.link_off)),
          ],
        ],
      ),
      body: !connected
          ? EmptyState(
              icon: Icons.star_outline,
              text:
                  'Connecte ton compte Patreon pour retrouver les créateurs que tu soutiens et écouter leurs épisodes premium.',
              action: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: premiumColor),
                onPressed: _connect,
                icon: const Icon(Icons.login),
                label: const Text('Connecter Patreon'),
              ),
            )
          : AsyncView<List<PatreonCampaign>>(
              ref.watch(patreonCampaignsProvider),
              onRetry: () => ref.invalidate(patreonCampaignsProvider),
              builder: (list) => list.isEmpty
                  ? EmptyState(
                      icon: Icons.people_outline,
                      text: 'Aucun abonnement Patreon actif trouvé.',
                      action: OutlinedButton(onPressed: _sync, child: const Text('Synchroniser')),
                    )
                  : ListView(children: [
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                            'Sur Patreon, ouvre la page du créateur → « Écouter sur d’autres applis » pour copier ton lien RSS privé, puis colle-le ici.'),
                      ),
                      for (final c in list)
                        ListTile(
                          leading: Artwork(c.imageUrl),
                          title: Text(c.name),
                          subtitle: Text([
                            if (c.tierTitle != null) c.tierTitle!,
                            c.isLinked ? 'Flux associé' : 'Flux non associé',
                          ].join(' · ')),
                          trailing: c.isLinked
                              ? const Icon(Icons.check_circle, color: premiumColor)
                              : FilledButton.tonal(
                                  onPressed: () => _link(c), child: const Text('Associer')),
                          onTap: c.isLinked
                              ? () => context.push('/podcast/${c.podcastId}')
                              : () => _link(c),
                          onLongPress: c.isLinked ? () => _link(c) : null,
                        ),
                    ]),
            ),
    );
  }
}

class _LinkFeedDialog extends StatefulWidget {
  const _LinkFeedDialog(this.campaign);
  final PatreonCampaign campaign;

  @override
  State<_LinkFeedDialog> createState() => _LinkFeedDialogState();
}

class _LinkFeedDialogState extends State<_LinkFeedDialog> {
  final _url = TextEditingController();

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('Flux privé de ${widget.campaign.name}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: _url,
            autofocus: true,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'URL RSS Patreon',
              hintText: 'https://www.patreon.com/rss/…?auth=…',
            ),
          ),
          if (widget.campaign.url != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => unawaited(launchUrl(Uri.parse(widget.campaign.url!),
                    mode: LaunchMode.externalApplication)),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('Ouvrir la page Patreon'),
              ),
            ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(context, _url.text.trim()),
              child: const Text('Associer')),
        ],
      );
}
