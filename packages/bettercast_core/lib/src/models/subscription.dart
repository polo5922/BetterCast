import '../util/json.dart';
import 'podcast.dart';

class Subscription {
  const Subscription({
    required this.podcast,
    required this.subscribedAt,
    this.notify = true,
  });

  final Podcast podcast;
  final DateTime subscribedAt;

  /// Send a notification when a new episode is published.
  final bool notify;

  Json toJson() => {
        'podcast': podcast.toJson(),
        'subscribedAt': dateToJson(subscribedAt),
        'notify': notify,
      };

  factory Subscription.fromJson(Json j) => Subscription(
        podcast: Podcast.fromJson((j['podcast'] as Map).cast()),
        subscribedAt: parseDate(j['subscribedAt']) ?? DateTime.now().toUtc(),
        notify: j['notify'] as bool? ?? true,
      );
}
