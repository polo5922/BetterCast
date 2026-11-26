library;

import 'package:postgres/postgres.dart';

import 'src/api.dart';
import 'src/auth/auth_service.dart';
import 'src/config.dart';
import 'src/feeds/feed_fetcher.dart';
import 'src/feeds/podcast_repository.dart';
import 'src/security/crypto.dart';
import 'src/services/notification_service.dart';
import 'src/services/patreon_service.dart';
import 'src/services/search_service.dart';
import 'src/worker.dart';

export 'src/api.dart';
export 'src/auth/auth_service.dart';
export 'src/config.dart';
export 'src/db/migrations.dart';
export 'src/feeds/feed_fetcher.dart';
export 'src/feeds/podcast_repository.dart';
export 'src/http/json.dart';
export 'src/security/crypto.dart';
export 'src/services/notification_service.dart';
export 'src/services/patreon_service.dart';
export 'src/services/search_service.dart';
export 'src/worker.dart';

/// Wires every service together.
class App {
  App(this.db, this.config, {PasswordHasher? hasher}) {
    final crypto = Encryptor(config.encryptionKey);
    fetcher = FeedFetcher(userAgent: config.userAgent);
    podcasts = PodcastRepository(db, fetcher, crypto);
    notifications = NotificationService(db,
        fcmServiceAccountJson: config.fcmServiceAccountJson);
    events = EventHub(config.databaseUrl, podcasts.episodesByIds);
    final search = SearchService(
      podcastIndexKey: config.podcastIndexKey,
      podcastIndexSecret: config.podcastIndexSecret,
      userAgent: config.userAgent,
    );
    api = Api(
      db: db,
      config: config,
      auth: AuthService(db, config.jwtSecret, hasher: hasher),
      podcasts: podcasts,
      search: search,
      patreon: PatreonService(db, config, crypto, podcasts),
      events: events,
    );
    worker = RefreshWorker(podcasts, notifications,
        interval: config.refreshInterval);
  }

  final Pool db;
  final Config config;
  late final FeedFetcher fetcher;
  late final PodcastRepository podcasts;
  late final NotificationService notifications;
  late final EventHub events;
  late final Api api;
  late final RefreshWorker worker;

  Future<void> close() async {
    await events.close();
    notifications.close();
    fetcher.close();
  }
}
