import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Cover images saved on the device alongside downloaded episodes, so
/// covers (and the colors derived from them) still show offline.
class ArtworkCache {
  ArtworkCache._();

  static Directory? _dir;
  static final Set<String> _files = {};
  static final Map<String, Future<void>> _pending = {};

  static Future<void> init() async {
    final dir = Directory(p.join((await getApplicationSupportDirectory()).path, 'artwork'));
    await dir.create(recursive: true);
    _dir = dir;
    await for (final f in dir.list()) {
      if (f is File && !f.path.endsWith('.part')) _files.add(p.basename(f.path));
    }
  }

  /// Stable file name for [url]: two 32-bit FNV-1a hashes.
  static String _name(String url) {
    int fnv(int seed) {
      var h = seed;
      for (final c in url.codeUnits) {
        h = ((h ^ c) * 0x01000193) & 0xFFFFFFFF;
      }
      return h;
    }

    String hex(int v) => v.toRadixString(16).padLeft(8, '0');
    return '${hex(fnv(0x811c9dc5))}${hex(fnv(0x050c5d1f))}.img';
  }

  /// The local copy of [url], if it was saved.
  static File? fileFor(String? url) {
    final dir = _dir;
    if (url == null || url.isEmpty || dir == null) return null;
    final name = _name(url);
    return _files.contains(name) ? File(p.join(dir.path, name)) : null;
  }

  /// Downloads [url] once; errors are ignored (the network image is used).
  static Future<void> save(String? url) {
    final dir = _dir;
    if (url == null || url.isEmpty || dir == null || fileFor(url) != null) {
      return Future.value();
    }
    return _pending[url] ??= () async {
      final name = _name(url);
      final part = File(p.join(dir.path, '$name.part'));
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
      try {
        final res = await (await client.getUrl(Uri.parse(url))).close();
        if (res.statusCode != 200) return;
        await res.pipe(part.openWrite());
        await part.rename(p.join(dir.path, name));
        _files.add(name);
      } catch (_) {
        try {
          if (await part.exists()) await part.delete();
        } catch (_) {}
      } finally {
        client.close();
        _pending.remove(url);
      }
    }();
  }

  static Future<void> remove(String? url) async {
    final f = fileFor(url);
    if (f == null) return;
    _files.remove(p.basename(f.path));
    try {
      await f.delete();
    } catch (_) {}
  }
}
