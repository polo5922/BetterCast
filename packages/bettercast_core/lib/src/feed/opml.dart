import 'package:xml/xml.dart';

class OpmlEntry {
  const OpmlEntry({required this.feedUrl, this.title});
  final String feedUrl;
  final String? title;
}

/// Extracts every `<outline xmlUrl=...>` (nested outlines included).
List<OpmlEntry> parseOpml(String xml) {
  final doc = XmlDocument.parse(xml);
  final seen = <String>{};
  return [
    for (final o in doc.findAllElements('outline'))
      if (o.getAttribute('xmlUrl')?.trim() case final url?
          when url.isNotEmpty && seen.add(url))
        OpmlEntry(
          feedUrl: url,
          title: o.getAttribute('title') ?? o.getAttribute('text'),
        ),
  ];
}

String buildOpml(Iterable<OpmlEntry> entries, {String title = 'BetterCast'}) {
  final b = XmlBuilder()..processing('xml', 'version="1.0" encoding="UTF-8"');
  b.element('opml', attributes: {'version': '2.0'}, nest: () {
    b.element('head', nest: () => b.element('title', nest: title));
    b.element('body', nest: () {
      for (final e in entries) {
        b.element('outline', attributes: {
          'type': 'rss',
          'text': e.title ?? e.feedUrl,
          'title': e.title ?? e.feedUrl,
          'xmlUrl': e.feedUrl,
        });
      }
    });
  });
  return b.buildDocument().toXmlString(pretty: true);
}
