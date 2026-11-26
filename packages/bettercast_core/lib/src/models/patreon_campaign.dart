import '../util/json.dart';

/// A Patreon creator the user supports.
class PatreonCampaign {
  const PatreonCampaign({
    required this.id,
    required this.name,
    this.imageUrl,
    this.url,
    this.tierTitle,
    this.podcastId,
  });

  final String id;
  final String name;
  final String? imageUrl;
  final String? url;
  final String? tierTitle;

  /// Set once the user has linked this campaign's private RSS feed.
  final String? podcastId;

  bool get isLinked => podcastId != null;

  Json toJson() => {
        'id': id,
        'name': name,
        if (imageUrl != null) 'imageUrl': imageUrl,
        if (url != null) 'url': url,
        if (tierTitle != null) 'tierTitle': tierTitle,
        if (podcastId != null) 'podcastId': podcastId,
      };

  factory PatreonCampaign.fromJson(Json j) => PatreonCampaign(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        imageUrl: j['imageUrl'] as String?,
        url: j['url'] as String?,
        tierTitle: j['tierTitle'] as String?,
        podcastId: j['podcastId'] as String?,
      );
}
