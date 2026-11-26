import 'package:xml/xml.dart';

import '../models/chapter_link.dart';
import '../models/episode.dart';
import '../models/media_variant.dart';
import '../models/podcast.dart';
import '../models/transcript.dart';
import 'duration_parser.dart';

const itunesNs = 'http://www.itunes.com/dtds/podcast-1.0.dtd';
const contentNs = 'http://purl.org/rss/1.0/modules/content/';
const podcastNs = 'https://podcastindex.org/namespace/1.0';
const mediaNs = 'http://search.yahoo.com/mrss/';

class FeedParseException implements Exception {
  FeedParseException(this.message);
  final String message;
  @override
  String toString() => 'FeedParseException: $message';
}

class ParsedFeed {
  const ParsedFeed({required this.podcast, required this.episodes});
  final Podcast podcast;

  /// Most recent first.
  final List<Episode> episodes;
}

/// Parses RSS 2.0 podcast feeds, with the iTunes and Podcasting 2.0
/// namespaces (alternateEnclosure, transcript, chapters, guid) and Media RSS.
class FeedParser {
  const FeedParser();

  /// [podcastId] overrides the id derived from [feedUrl] (used for private
  /// feeds whose id must not depend on a secret URL). [premium] marks every
  /// episode as premium.
  ParsedFeed parse(
    String xml, {
    required String feedUrl,
    String? podcastId,
    PodcastSource source = PodcastSource.rss,
    bool premium = false,
  }) {
    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(xml);
    } on XmlException catch (e) {
      throw FeedParseException('Invalid XML: ${e.message}');
    }
    final channel = doc.rootElement.getElement('channel');
    if (doc.rootElement.name.local != 'rss' || channel == null) {
      throw FeedParseException('Not an RSS feed');
    }

    final id = podcastId ?? Podcast.idFor(feedUrl);
    final podcastImage = _attr(_child(channel, 'image', itunesNs), 'href') ??
        _text(channel.getElement('image')?.getElement('url'));

    final episodes = <Episode>[];
    final seen = <String>{};
    for (final item in channel.findElements('item')) {
      final ep = _parseItem(item, id, podcastImage, premium);
      if (ep != null && seen.add(ep.id)) episodes.add(ep);
    }
    episodes.sort((a, b) {
      final da = a.publishedAt, db = b.publishedAt;
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;
      return db.compareTo(da);
    });

    final podcast = Podcast(
      id: id,
      feedUrl: Podcast.normalizeFeedUrl(feedUrl),
      title: _text(channel.getElement('title')) ?? 'Untitled',
      author: _text(_child(channel, 'author', itunesNs)) ??
          _text(channel.getElement('managingEditor')),
      description: _text(channel.getElement('description')) ??
          _text(_child(channel, 'summary', itunesNs)) ??
          '',
      imageUrl: podcastImage,
      link: _text(channel.getElement('link')),
      language: _text(channel.getElement('language')),
      categories: _categories(channel),
      explicit: _bool(_text(_child(channel, 'explicit', itunesNs))),
      source: source,
      podcastGuid: _text(_child(channel, 'guid', podcastNs)),
      lastEpisodeAt: episodes.firstOrNull?.publishedAt,
      episodeCount: episodes.length,
    );
    return ParsedFeed(podcast: podcast, episodes: episodes);
  }

  Episode? _parseItem(
    XmlElement item,
    String podcastId,
    String? podcastImage,
    bool premium,
  ) {
    final variants = <MediaVariant>[];
    void add(MediaVariant v) {
      if (v.url.isEmpty) return;
      final i = variants.indexWhere((e) => e.url == v.url);
      if (i == -1) {
        variants.add(v);
      } else if (v.isDefault && !variants[i].isDefault) {
        variants[i] = v;
      }
    }

    final enclosure = item.getElement('enclosure');
    final encUrl = _attr(enclosure, 'url');
    if (encUrl != null) {
      add(MediaVariant(
        url: encUrl,
        mimeType: _attr(enclosure, 'type') ?? '',
        length: int.tryParse(_attr(enclosure, 'length') ?? ''),
        isDefault: true,
      ));
    }

    for (final alt in _children(item, 'alternateEnclosure', podcastNs)) {
      final src = _children(alt, 'source', podcastNs)
          .map((s) => _attr(s, 'uri'))
          .whereType<String>()
          .where((u) => u.startsWith('http'))
          .firstOrNull;
      if (src == null) continue;
      add(MediaVariant(
        url: src,
        mimeType: _attr(alt, 'type') ?? '',
        length: int.tryParse(_attr(alt, 'length') ?? ''),
        bitrate: double.tryParse(_attr(alt, 'bitrate') ?? ''),
        height: int.tryParse(_attr(alt, 'height') ?? ''),
        title: _attr(alt, 'title'),
        isDefault: _bool(_attr(alt, 'default')) && encUrl == null,
      ));
    }

    final mediaContents = [
      ..._children(item, 'content', mediaNs),
      for (final g in _children(item, 'group', mediaNs))
        ..._children(g, 'content', mediaNs),
    ];
    for (final mc in mediaContents) {
      final url = _attr(mc, 'url');
      if (url == null) continue;
      final medium = _attr(mc, 'medium');
      var type = _attr(mc, 'type') ?? '';
      if (type.isEmpty && medium != null) type = '$medium/*';
      if (medium != null && medium != 'audio' && medium != 'video') continue;
      if (type.startsWith('image/')) continue;
      add(MediaVariant(
        url: url,
        mimeType: type,
        length: int.tryParse(_attr(mc, 'fileSize') ?? ''),
        height: int.tryParse(_attr(mc, 'height') ?? ''),
        isDefault: false,
      ));
    }

    final title = _text(item.getElement('title')) ??
        _text(_child(item, 'title', itunesNs));
    if (variants.isEmpty || title == null) return null;

    final pubDate = parseFeedDate(_text(item.getElement('pubDate')));
    final guid = _text(item.getElement('guid')) ??
        encUrl ??
        '$title|${pubDate?.toIso8601String() ?? ''}';

    final content = _text(_child(item, 'encoded', contentNs));
    final description = _text(item.getElement('description'));
    final summary = _text(_child(item, 'subtitle', itunesNs)) ??
        _text(_child(item, 'summary', itunesNs));

    final chaptersEl = _child(item, 'chapters', podcastNs);
    final chaptersUrl = _attr(chaptersEl, 'url');

    return Episode(
      id: Episode.idFor(podcastId, guid),
      podcastId: podcastId,
      guid: guid,
      title: title,
      description: content ?? description ?? summary ?? '',
      summary: summary ?? (content != null ? description : null),
      link: _text(item.getElement('link')),
      imageUrl: _attr(_child(item, 'image', itunesNs), 'href') ?? podcastImage,
      publishedAt: pubDate,
      duration: parseItunesDuration(_text(_child(item, 'duration', itunesNs))),
      season: int.tryParse(_text(_child(item, 'season', itunesNs)) ??
          _text(_child(item, 'season', podcastNs)) ??
          ''),
      number: int.tryParse(_text(_child(item, 'episode', itunesNs)) ??
          _text(_child(item, 'episode', podcastNs)) ??
          ''),
      explicit: _bool(_text(_child(item, 'explicit', itunesNs))),
      premium: premium,
      variants: variants,
      transcripts: [
        for (final t in _children(item, 'transcript', podcastNs))
          if (_attr(t, 'url') case final url?)
            Transcript(
              url: url,
              type: _attr(t, 'type') ?? '',
              language: _attr(t, 'language'),
              rel: _attr(t, 'rel'),
            ),
      ],
      chapters: chaptersUrl == null
          ? null
          : ChapterLink(
              url: chaptersUrl,
              type: _attr(chaptersEl, 'type') ?? 'application/json+chapters',
            ),
    );
  }

  List<String> _categories(XmlElement channel) {
    final out = <String>{};
    void walk(XmlElement e) {
      final t = _attr(e, 'text');
      if (t != null) out.add(t);
      _children(e, 'category', itunesNs).forEach(walk);
    }

    _children(channel, 'category', itunesNs).forEach(walk);
    return out.toList();
  }

  // ---- helpers ----------------------------------------------------------

  /// Matches by namespace URI, falling back to the conventional prefix for
  /// feeds that forget to declare the namespace.
  Iterable<XmlElement> _children(XmlElement parent, String local, String ns) =>
      parent.childElements.where((e) =>
          e.name.local == local &&
          (e.name.namespaceUri == ns ||
              (e.name.namespaceUri == null &&
                  e.name.prefix == _prefixFor(ns))));

  XmlElement? _child(XmlElement parent, String local, String ns) =>
      _children(parent, local, ns).firstOrNull;

  String? _prefixFor(String ns) => switch (ns) {
        itunesNs => 'itunes',
        contentNs => 'content',
        podcastNs => 'podcast',
        mediaNs => 'media',
        _ => null,
      };

  String? _attr(XmlElement? e, String name) {
    final v = e?.getAttribute(name)?.trim();
    return v == null || v.isEmpty ? null : v;
  }

  String? _text(XmlElement? e) {
    final v = e?.innerText.trim();
    return v == null || v.isEmpty ? null : v;
  }

  bool _bool(String? v) =>
      const {'yes', 'true', 'explicit', '1'}.contains(v?.toLowerCase());
}
