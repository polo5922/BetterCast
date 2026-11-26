import '../util/json.dart';

/// Per-user playback state of an episode, synced between devices.
/// Conflicts are resolved last-write-wins on [updatedAt].
class EpisodeState {
  const EpisodeState({
    required this.episodeId,
    this.podcastId,
    this.position = Duration.zero,
    this.played = false,
    this.liked = false,
    required this.updatedAt,
  });

  final String episodeId;
  final String? podcastId;
  final Duration position;
  final bool played;
  final bool liked;
  final DateTime updatedAt;

  bool get inProgress => !played && position > const Duration(seconds: 5);

  EpisodeState copyWith({
    Duration? position,
    bool? played,
    bool? liked,
    DateTime? updatedAt,
  }) =>
      EpisodeState(
        episodeId: episodeId,
        podcastId: podcastId,
        position: position ?? this.position,
        played: played ?? this.played,
        liked: liked ?? this.liked,
        updatedAt: updatedAt ?? DateTime.now().toUtc(),
      );

  /// Returns whichever of the two states is the most recent.
  static EpisodeState merge(EpisodeState a, EpisodeState b) =>
      b.updatedAt.isAfter(a.updatedAt) ? b : a;

  Json toJson() => {
        'episodeId': episodeId,
        if (podcastId != null) 'podcastId': podcastId,
        'positionMs': position.inMilliseconds,
        'played': played,
        'liked': liked,
        'updatedAt': dateToJson(updatedAt),
      };

  factory EpisodeState.fromJson(Json j) => EpisodeState(
        episodeId: j['episodeId'] as String,
        podcastId: j['podcastId'] as String?,
        position:
            Duration(milliseconds: (j['positionMs'] as num?)?.toInt() ?? 0),
        played: j['played'] as bool? ?? false,
        liked: j['liked'] as bool? ?? false,
        updatedAt: parseDate(j['updatedAt']) ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );
}
