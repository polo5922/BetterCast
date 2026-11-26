import '../models/episode.dart';
import '../models/podcast.dart';
import '../util/json.dart';

/// JSON contracts between the app and the BetterCast server.

class AuthTokens {
  const AuthTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;

  Json toJson() => {
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'expiresAt': dateToJson(expiresAt),
      };

  factory AuthTokens.fromJson(Json j) => AuthTokens(
        accessToken: j['accessToken'] as String,
        refreshToken: j['refreshToken'] as String,
        expiresAt: parseDate(j['expiresAt']) ?? DateTime.now().toUtc(),
      );
}

class UserProfile {
  const UserProfile({
    required this.id,
    required this.email,
    this.displayName,
    this.patreonConnected = false,
  });

  final String id;
  final String email;
  final String? displayName;
  final bool patreonConnected;

  Json toJson() => {
        'id': id,
        'email': email,
        if (displayName != null) 'displayName': displayName,
        'patreonConnected': patreonConnected,
      };

  factory UserProfile.fromJson(Json j) => UserProfile(
        id: j['id'] as String,
        email: j['email'] as String,
        displayName: j['displayName'] as String?,
        patreonConnected: j['patreonConnected'] as bool? ?? false,
      );
}

/// Response of login / register.
class AuthResponse {
  const AuthResponse({required this.user, required this.tokens});
  final UserProfile user;
  final AuthTokens tokens;

  Json toJson() => {'user': user.toJson(), 'tokens': tokens.toJson()};

  factory AuthResponse.fromJson(Json j) => AuthResponse(
        user: UserProfile.fromJson((j['user'] as Map).cast()),
        tokens: AuthTokens.fromJson((j['tokens'] as Map).cast()),
      );
}

/// A podcast found by search (Podcast Index / iTunes).
class SearchResult {
  const SearchResult({
    required this.feedUrl,
    required this.title,
    this.author,
    this.imageUrl,
    this.description,
    this.episodeCount,
    this.hasVideo = false,
  });

  final String feedUrl;
  final String title;
  final String? author;
  final String? imageUrl;
  final String? description;
  final int? episodeCount;
  final bool hasVideo;

  String get podcastId => Podcast.idFor(feedUrl);

  Json toJson() => {
        'feedUrl': feedUrl,
        'title': title,
        if (author != null) 'author': author,
        if (imageUrl != null) 'imageUrl': imageUrl,
        if (description != null) 'description': description,
        if (episodeCount != null) 'episodeCount': episodeCount,
        'hasVideo': hasVideo,
      };

  factory SearchResult.fromJson(Json j) => SearchResult(
        feedUrl: j['feedUrl'] as String,
        title: j['title'] as String? ?? '',
        author: j['author'] as String?,
        imageUrl: j['imageUrl'] as String?,
        description: j['description'] as String?,
        episodeCount: (j['episodeCount'] as num?)?.toInt(),
        hasVideo: j['hasVideo'] as bool? ?? false,
      );
}

class PodcastDetail {
  const PodcastDetail({
    required this.podcast,
    required this.episodes,
    this.subscribed = false,
  });

  final Podcast podcast;
  final List<Episode> episodes;
  final bool subscribed;

  Json toJson() => {
        'podcast': podcast.toJson(),
        'episodes': episodes.map((e) => e.toJson()).toList(),
        'subscribed': subscribed,
      };

  factory PodcastDetail.fromJson(Json j) => PodcastDetail(
        podcast: Podcast.fromJson((j['podcast'] as Map).cast()),
        episodes: parseList(j['episodes'], Episode.fromJson),
        subscribed: j['subscribed'] as bool? ?? false,
      );
}

/// An episode with the info needed to show it outside its podcast page
/// (new releases feed, notifications, Android Auto).
class FeedItem {
  const FeedItem({required this.episode, required this.podcast});
  final Episode episode;
  final Podcast podcast;

  Json toJson() => {'episode': episode.toJson(), 'podcast': podcast.toJson()};

  factory FeedItem.fromJson(Json j) => FeedItem(
        episode: Episode.fromJson((j['episode'] as Map).cast()),
        podcast: Podcast.fromJson((j['podcast'] as Map).cast()),
      );
}

/// Payload of a "new episode" push / SSE event.
class NewEpisodeEvent {
  const NewEpisodeEvent({
    required this.episodeId,
    required this.podcastId,
    required this.podcastTitle,
    required this.title,
    this.summary,
    this.imageUrl,
    this.premium = false,
    this.hasVideo = false,
    this.publishedAt,
  });

  final String episodeId;
  final String podcastId;
  final String podcastTitle;
  final String title;
  final String? summary;
  final String? imageUrl;
  final bool premium;
  final bool hasVideo;
  final DateTime? publishedAt;

  factory NewEpisodeEvent.fromItem(FeedItem item) => NewEpisodeEvent(
        episodeId: item.episode.id,
        podcastId: item.podcast.id,
        podcastTitle: item.podcast.title,
        title: item.episode.title,
        summary: item.episode.summary,
        imageUrl: item.episode.imageUrl ?? item.podcast.imageUrl,
        premium: item.episode.premium,
        hasVideo: item.episode.hasVideo,
        publishedAt: item.episode.publishedAt,
      );

  /// FCM data payloads only carry strings.
  Map<String, String> toStringMap() => {
        'type': 'new_episode',
        'episodeId': episodeId,
        'podcastId': podcastId,
        'podcastTitle': podcastTitle,
        'title': title,
        if (summary != null) 'summary': summary!,
        if (imageUrl != null) 'imageUrl': imageUrl!,
        'premium': '$premium',
        'hasVideo': '$hasVideo',
        if (publishedAt != null) 'publishedAt': dateToJson(publishedAt)!,
      };

  Json toJson() => toStringMap();

  factory NewEpisodeEvent.fromJson(Map<String, dynamic> j) => NewEpisodeEvent(
        episodeId: j['episodeId'] as String,
        podcastId: j['podcastId'] as String,
        podcastTitle: j['podcastTitle'] as String? ?? '',
        title: j['title'] as String? ?? '',
        summary: j['summary'] as String?,
        imageUrl: j['imageUrl'] as String?,
        premium: '${j['premium']}' == 'true',
        hasVideo: '${j['hasVideo']}' == 'true',
        publishedAt: parseDate(j['publishedAt']),
      );
}

enum DevicePlatform { android, windows }

class DeviceRegistration {
  const DeviceRegistration({
    required this.deviceId,
    required this.platform,
    this.pushToken,
    this.name,
  });

  final String deviceId;
  final DevicePlatform platform;

  /// FCM token (Android). Windows devices receive events via SSE.
  final String? pushToken;
  final String? name;

  Json toJson() => {
        'deviceId': deviceId,
        'platform': platform.name,
        if (pushToken != null) 'pushToken': pushToken,
        if (name != null) 'name': name,
      };

  factory DeviceRegistration.fromJson(Json j) => DeviceRegistration(
        deviceId: j['deviceId'] as String,
        platform: DevicePlatform.values.asNameMap()[j['platform']] ??
            DevicePlatform.android,
        pushToken: j['pushToken'] as String?,
        name: j['name'] as String?,
      );
}

class ApiError {
  const ApiError(this.code, this.message);
  final String code;
  final String message;

  Json toJson() => {'error': code, 'message': message};

  factory ApiError.fromJson(Json j) =>
      ApiError(j['error'] as String? ?? 'unknown', j['message'] as String? ?? '');
}
