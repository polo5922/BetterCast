import '../util/json.dart';

/// A `podcast:transcript` reference. Stored in V1, rendered as synced
/// "lyrics" in V2.
class Transcript {
  const Transcript({required this.url, required this.type, this.language, this.rel});

  final String url;

  /// MIME type: text/vtt, application/x-subrip, application/json, text/html...
  final String type;
  final String? language;
  final String? rel;

  /// True for formats carrying timestamps (usable for synced display).
  bool get isTimed => const {
        'text/vtt',
        'application/x-subrip',
        'application/srt',
        'application/json',
      }.contains(type.toLowerCase());

  Json toJson() => {
        'url': url,
        'type': type,
        if (language != null) 'language': language,
        if (rel != null) 'rel': rel,
      };

  factory Transcript.fromJson(Json j) => Transcript(
        url: j['url'] as String,
        type: j['type'] as String? ?? '',
        language: j['language'] as String?,
        rel: j['rel'] as String?,
      );
}
