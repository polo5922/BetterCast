import '../util/json.dart';

/// A `podcast:chapters` reference (JSON chapters file).
class ChapterLink {
  const ChapterLink({required this.url, required this.type});

  final String url;
  final String type;

  Json toJson() => {'url': url, 'type': type};

  factory ChapterLink.fromJson(Json j) =>
      ChapterLink(url: j['url'] as String, type: j['type'] as String? ?? '');
}
