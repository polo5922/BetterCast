import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';

final _log = Logger('migrations');

/// Versioned schema migrations. Append only: never edit a released entry.
const migrations = <int, String>{
  1: r'''
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE users (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email         text NOT NULL UNIQUE,
  password_hash text NOT NULL,
  display_name  text,
  created_at    timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE refresh_tokens (
  token_hash  text PRIMARY KEY,
  user_id     uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  expires_at  timestamptz NOT NULL,
  revoked_at  timestamptz,
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX refresh_tokens_user ON refresh_tokens(user_id);

-- Public feeds are shared by every user (feed_url set). Private feeds
-- (Patreon) belong to one user and their URL is only stored encrypted.
CREATE TABLE podcasts (
  id               text PRIMARY KEY,
  feed_url         text UNIQUE,
  private_feed_enc text,
  owner_user_id    uuid REFERENCES users(id) ON DELETE CASCADE,
  source           text NOT NULL DEFAULT 'rss',
  title            text NOT NULL DEFAULT '',
  data             jsonb NOT NULL DEFAULT '{}',
  etag             text,
  last_modified    text,
  last_fetched_at  timestamptz,
  next_fetch_at    timestamptz NOT NULL DEFAULT now(),
  fail_count       int NOT NULL DEFAULT 0,
  last_error       text,
  created_at       timestamptz NOT NULL DEFAULT now(),
  CHECK (feed_url IS NOT NULL OR private_feed_enc IS NOT NULL)
);
CREATE INDEX podcasts_next_fetch ON podcasts(next_fetch_at);

CREATE TABLE episodes (
  id            text PRIMARY KEY,
  podcast_id    text NOT NULL REFERENCES podcasts(id) ON DELETE CASCADE,
  guid          text NOT NULL,
  published_at  timestamptz,
  data          jsonb NOT NULL,
  first_seen_at timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX episodes_podcast_pub ON episodes(podcast_id, published_at DESC NULLS LAST);

CREATE TABLE subscriptions (
  user_id       uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  podcast_id    text NOT NULL REFERENCES podcasts(id) ON DELETE CASCADE,
  subscribed_at timestamptz NOT NULL DEFAULT now(),
  notify        boolean NOT NULL DEFAULT true,
  PRIMARY KEY (user_id, podcast_id)
);
CREATE INDEX subscriptions_podcast ON subscriptions(podcast_id);

CREATE TABLE episode_states (
  user_id     uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  episode_id  text NOT NULL,
  podcast_id  text,
  position_ms bigint NOT NULL DEFAULT 0,
  played      boolean NOT NULL DEFAULT false,
  liked       boolean NOT NULL DEFAULT false,
  updated_at  timestamptz NOT NULL,
  synced_at   timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, episode_id)
);
CREATE INDEX episode_states_sync ON episode_states(user_id, synced_at);

CREATE TABLE devices (
  user_id    uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  device_id  text NOT NULL,
  platform   text NOT NULL,
  push_token text,
  name       text,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, device_id)
);

CREATE TABLE patreon_accounts (
  user_id           uuid PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  patreon_user_id   text NOT NULL,
  access_token_enc  text NOT NULL,
  refresh_token_enc text NOT NULL,
  expires_at        timestamptz NOT NULL,
  updated_at        timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE patreon_campaigns (
  user_id     uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  campaign_id text NOT NULL,
  name        text NOT NULL,
  image_url   text,
  url         text,
  tier_title  text,
  podcast_id  text REFERENCES podcasts(id) ON DELETE SET NULL,
  updated_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, campaign_id)
);

CREATE TABLE oauth_states (
  state      text PRIMARY KEY,
  user_id    uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now()
);
''',
};

Future<void> runMigrations(Pool pool) async {
  await pool.execute('''
CREATE TABLE IF NOT EXISTS schema_migrations (
  version    int PRIMARY KEY,
  applied_at timestamptz NOT NULL DEFAULT now()
)''');
  // Serialize concurrent starts (api + worker) with an advisory lock.
  await pool.runTx((tx) async {
    await tx.execute('SELECT pg_advisory_xact_lock(424242)');
    final done = (await tx.execute('SELECT version FROM schema_migrations'))
        .map((r) => r[0] as int)
        .toSet();
    final pending = migrations.keys.where((v) => !done.contains(v)).toList()
      ..sort();
    for (final v in pending) {
      _log.info('Applying migration $v');
      await tx.execute(migrations[v]!, queryMode: QueryMode.simple);
      await tx.execute(
        Sql.named('INSERT INTO schema_migrations(version) VALUES (@v)'),
        parameters: {'v': v},
      );
    }
  });
}
