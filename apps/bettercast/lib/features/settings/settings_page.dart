import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auto_downloads.dart';
import '../../core/onboarding.dart';
import '../../core/config.dart';
import '../../core/providers.dart';
import '../../ui/widgets.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() task) async {
    setState(() => _busy = true);
    try {
      await task();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _importOpml() => _run(() async {
        final files = await FilePicker.pickFiles(
          type: FileType.custom,
          allowedExtensions: const ['opml', 'xml'],
        );
        if (files.isEmpty) return;
        final opml = await files.first.xFile.readAsString();
        final r = await ref.read(apiProvider).importOpml(opml);
        ref.invalidate(subscriptionsProvider);
        ref.invalidate(newReleasesProvider);
        _toast('${r.imported} podcasts importés'
            '${r.failed.isEmpty ? '' : ', ${r.failed.length} en échec'}');
      });

  Future<void> _exportOpml() => _run(() async {
        final opml = await ref.read(apiProvider).exportOpml();
        final uri = await FilePicker.saveFile(
          fileName: 'bettercast.opml',
          bytes: utf8.encode(opml),
          mimeType: 'text/x-opml',
        );
        if (uri != null) _toast('Abonnements exportés');
      });

  Future<void> _addPrivateFeed() async {
    final ctl = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Ajouter un flux privé'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: 'URL du flux RSS',
            helperText: 'Le lien est chiffré sur ton serveur et n’est jamais partagé.',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(c, ctl.text.trim()), child: const Text('Ajouter')),
        ],
      ),
    );
    if (url == null || url.isEmpty) return;
    await _run(() async {
      final d = await ref.read(apiProvider).addPrivateFeed(url);
      ref.invalidate(subscriptionsProvider);
      ref.invalidate(newReleasesProvider);
      if (mounted) context.push('/podcast/${d.podcast.id}');
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final user = session.user;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Réglages'),
        bottom: _busy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2), child: LinearProgressIndicator(minHeight: 2))
            : null,
      ),
      body: ListView(children: [
        ListTile(
          leading: const CircleAvatar(child: Icon(Icons.person)),
          title: Text(user?.displayName ?? user?.email ?? ''),
          subtitle: Text([
            if (user?.displayName != null) user!.email,
            if (session.serverUrl != null) session.serverUrl!,
          ].join('\n')),
          isThreeLine: user?.displayName != null,
        ),
        ListTile(
          leading: const Icon(Icons.waving_hand_outlined),
          title: const Text('Revoir la présentation'),
          onTap: () => ref.read(onboardingDoneProvider.notifier).replay(),
        ),
        const Divider(),
        _section(context, 'Abonnements'),
        ListTile(
          leading: const Icon(Icons.file_upload_outlined),
          title: const Text('Importer un fichier OPML'),
          subtitle: const Text('Depuis une autre app de podcasts'),
          onTap: _busy ? null : _importOpml,
        ),
        ListTile(
          leading: const Icon(Icons.file_download_outlined),
          title: const Text('Exporter en OPML'),
          onTap: _busy ? null : _exportOpml,
        ),
        ListTile(
          leading: const Icon(Icons.lock_outline),
          title: const Text('Ajouter un flux RSS privé'),
          onTap: _busy ? null : _addPrivateFeed,
        ),
        ListTile(
          leading: const Icon(Icons.star_outline, color: premiumColor),
          title: const Text('Patreon'),
          subtitle: Text(user?.patreonConnected == true ? 'Connecté' : 'Non connecté'),
          onTap: () => context.push('/patreon'),
        ),
        const Divider(),
        _section(context, 'Téléchargements'),
        SwitchListTile(
          secondary: const Icon(Icons.wifi),
          title: const Text('Téléchargement auto en Wi-Fi uniquement'),
          subtitle: const Text(
              'Active-le podcast par podcast avec l’icône de téléchargement sur sa page'),
          value: ref.read(autoDownloadsProvider.notifier).wifiOnly,
          onChanged: (v) => setState(() => ref.read(autoDownloadsProvider.notifier).wifiOnly = v),
        ),
        const Divider(),
        _section(context, 'Synchronisation'),
        ListTile(
          leading: const Icon(Icons.sync),
          title: const Text('Synchroniser maintenant'),
          subtitle: const Text('Positions de lecture, likes, épisodes écoutés'),
          onTap: _busy
              ? null
              : () => _run(() async {
                    await ref.read(episodeStatesProvider.notifier).sync();
                    ref.invalidate(subscriptionsProvider);
                    ref.invalidate(newReleasesProvider);
                    _toast('Synchronisé');
                  }),
        ),
        ListTile(
          leading: const Icon(Icons.dns_outlined),
          title: const Text('Serveur'),
          subtitle: Text(session.serverUrl == normalizeServerUrl(kOfficialServer)
              ? 'Serveur officiel BetterCast'
              : session.serverUrl ?? ''),
        ),
        ListTile(
          leading: const Icon(Icons.open_in_new),
          title: const Text('Héberger son propre serveur'),
          subtitle: const Text('Guide sur GitHub'),
          onTap: () =>
              launchUrl(Uri.parse(kSelfHostGuideUrl), mode: LaunchMode.externalApplication),
        ),
        const Divider(),
        ListTile(
          leading: Icon(Icons.logout, color: Theme.of(context).colorScheme.error),
          title: Text('Se déconnecter',
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
          onTap: () => ref.read(sessionProvider.notifier).signOut(),
        ),
        const AboutListTile(
          icon: Icon(Icons.info_outline),
          applicationName: 'BetterCast',
          applicationVersion: '1.0.0',
        ),
      ]),
    );
  }

  Widget _section(BuildContext context, String title) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Text(title,
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(color: Theme.of(context).colorScheme.primary)),
      );
}
