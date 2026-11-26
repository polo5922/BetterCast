import '../util/json.dart';
import 'chapter_link.dart';
import 'media_variant.dart';
import 'transcript.dart';

class Episode {
  const Episode({
    required this.id,
    required this.podcastId,
    required this.guid,
    required this.title,
    this.description = '',
    this.summary,
    this.link,
    this.imageUrl,
    this.publishedAt,
    this.duration,
    this.season,
    this.number,
    this.explicit = false,
    this.premium = false,
    this.variants = const [],
    this.transcripts = const [],
    this.chapters,
  });

  /// `Episode.idFor(podcastId, guid)`.
  final String id;
  final String podcastId;
  final String guid;
  final String title;

  /// HTML (content:encoded or description).
  final String description;

  /// Short plain-text summary (itunes:summary / subtitle).
  final String? summary;
  final String? link;
  final String? imageUrl;
  final DateTime? publishedAt;
  final Duration? duration;
  final int? season;
  final int? number;
  final bool explicit;

  /// True for episodes coming from a private (e.g. Patreon) feed.
  final bool premium;
  final List<MediaVariant> variants;
  final List<Transcript> transcripts;
  final ChapterLink? chapters;

  static String idFor(String podcastId, String guid) => stableId([podcastId, guid]);

  MediaVariant? get audio => _best(MediaKind.audio);
  MediaVariant? get video => _best(MediaKind.video);
  bool get hasAudio => audio != null;
  bool get hasVideo => video != null;
  bool get canSwitchMedia => hasAudio && hasVideo;

  /// The variant played by default: the feed's main enclosure.
  MediaVariant? get defaultVariant =>
      variants.where((v) => v.isDefault).firstOrNull ?? variants.firstOrNull;

  MediaVariant? _best(MediaKind kind) {
    final c = variants.where((v) => v.kind == kind).toList();
    if (c.isEmpty) return null;
    c.sort((a, b) {
      if (a.isDefault != b.isDefault) return a.isDefault ? -1 : 1;
      return (b.height ?? 0).compareTo(a.height ?? 0);
    });
    return c.first;
  }

  Episode copyWith({
    String? id,
    String? podcastId,
    bool? premium,
    String? imageUrl,
  }) =>
      Episode(
        id: id ?? this.id,
        podcastId: podcastId ?? this.podcastId,
        guid: guid,
        title: title,
        description: description,
        summary: summary,
        link: link,
        imageUrl: imageUrl ?? this.imageUrl,
        publishedAt: publishedAt,
        duration: duration,
        season: season,
        number: number,
        explicit: explicit,
        premium: premium ?? this.premium,
        variants: variants,
        transcripts: transcripts,
        chapters: chapters,
      );

  Json toJson() => {
        'id': id,
        'podcastId': podcastId,
        'guid': guid,
        'title': title,
        'description': description,
        if (summary != null) 'summary': summary,
        if (link != null) 'link': link,
        if (imageUrl != null) 'imageUrl': imageUrl,
        if (publishedAt != null) 'publishedAt': dateToJson(publishedAt),
        if (duration != null) 'durationSec': duration!.inSeconds,
        if (season != null) 'season': season,
        if (number != null) 'number': number,
        'explicit': explicit,
        'premium': premium,
        'variants': variants.map((v) => v.toJson()).toList(),
        'transcripts': transcripts.map((t) => t.toJson()).toList(),
        if (chapters != null) 'chapters': chapters!.toJson(),
      };

  factory Episode.fromJson(Json j) => Episode(
        id: j['id'] as String,
        podcastId: j['podcastId'] as String,
        guid: j['guid'] as String,
        title: j['title'] as String? ?? '',
        description: j['description'] as String? ?? '',
        summary: j['summary'] as String?,
        link: j['link'] as String?,
        imageUrl: j['imageUrl'] as String?,
        publishedAt: parseDate(j['publishedAt']),
        duration: j['durationSec'] == null
            ? null
            : Duration(seconds: (j['durationSec'] as num).toInt()),
        season: (j['season'] as num?)?.toInt(),
        number: (j['number'] as num?)?.toInt(),
        explicit: j['explicit'] as bool? ?? false,
        premium: j['premium'] as bool? ?? false,
        variants: parseList(j['variants'], MediaVariant.fromJson),
        transcripts: parseList(j['transcripts'], Transcript.fromJson),
        chapters: j['chapters'] is Map
            ? ChapterLink.fromJson((j['chapters'] as Map).cast())
            : null,
      );
}
