import '../util/json.dart';

enum PodcastSource { rss, patreon }

class Podcast {
  const Podcast({
    required this.id,
    required this.feedUrl,
    required this.title,
    this.author,
    this.description = '',
    this.imageUrl,
    this.link,
    this.language,
    this.categories = const [],
    this.explicit = false,
    this.source = PodcastSource.rss,
    this.podcastGuid,
    this.lastEpisodeAt,
    this.episodeCount,
  });

  /// `Podcast.idFor(feedUrl)` for public feeds. For private feeds the server
  /// assigns a random id that never reveals the secret URL.
  final String id;

  /// Public feed URL. Empty for private feeds when sent to clients.
  final String feedUrl;
  final String title;
  final String? author;
  final String description;
  final String? imageUrl;
  final String? link;
  final String? language;
  final List<String> categories;
  final bool explicit;
  final PodcastSource source;
  final String? podcastGuid;
  final DateTime? lastEpisodeAt;
  final int? episodeCount;

  bool get isPremium => source == PodcastSource.patreon;

  static String idFor(String feedUrl) => stableId([normalizeFeedUrl(feedUrl)]);

  static String normalizeFeedUrl(String url) {
    var u = url.trim();
    for (final scheme in const ['feed://', 'itpc://', 'pcast://']) {
      if (u.startsWith(scheme)) u = 'https://${u.substring(scheme.length)}';
    }
    if (!u.contains('://')) u = 'https://$u';
    return u;
  }

  Podcast copyWith({
    String? id,
    String? feedUrl,
    PodcastSource? source,
    String? imageUrl,
    String? title,
    DateTime? lastEpisodeAt,
    int? episodeCount,
  }) =>
      Podcast(
        id: id ?? this.id,
        feedUrl: feedUrl ?? this.feedUrl,
        title: title ?? this.title,
        author: author,
        description: description,
        imageUrl: imageUrl ?? this.imageUrl,
        link: link,
        language: language,
        categories: categories,
        explicit: explicit,
        source: source ?? this.source,
        podcastGuid: podcastGuid,
        lastEpisodeAt: lastEpisodeAt ?? this.lastEpisodeAt,
        episodeCount: episodeCount ?? this.episodeCount,
      );

  Json toJson() => {
        'id': id,
        'feedUrl': feedUrl,
        'title': title,
        if (author != null) 'author': author,
        'description': description,
        if (imageUrl != null) 'imageUrl': imageUrl,
        if (link != null) 'link': link,
        if (language != null) 'language': language,
        'categories': categories,
        'explicit': explicit,
        'source': source.name,
        if (podcastGuid != null) 'podcastGuid': podcastGuid,
        if (lastEpisodeAt != null) 'lastEpisodeAt': dateToJson(lastEpisodeAt),
        if (episodeCount != null) 'episodeCount': episodeCount,
      };

  factory Podcast.fromJson(Json j) => Podcast(
        id: j['id'] as String,
        feedUrl: j['feedUrl'] as String? ?? '',
        title: j['title'] as String? ?? '',
        author: j['author'] as String?,
        description: j['description'] as String? ?? '',
        imageUrl: j['imageUrl'] as String?,
        link: j['link'] as String?,
        language: j['language'] as String?,
        categories: (j['categories'] as List?)?.cast<String>() ?? const [],
        explicit: j['explicit'] as bool? ?? false,
        source:
            PodcastSource.values.asNameMap()[j['source']] ?? PodcastSource.rss,
        podcastGuid: j['podcastGuid'] as String?,
        lastEpisodeAt: parseDate(j['lastEpisodeAt']),
        episodeCount: (j['episodeCount'] as num?)?.toInt(),
      );
}
