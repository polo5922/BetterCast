import 'dart:convert';
import 'dart:io';

/// Server configuration, read from environment variables (see `.env.example`).
class Config {
  Config({
    required this.port,
    required this.databaseUrl,
    required this.publicUrl,
    required this.jwtSecret,
    required this.encryptionKey,
    this.podcastIndexKey,
    this.podcastIndexSecret,
    this.patreonClientId,
    this.patreonClientSecret,
    this.fcmServiceAccountJson,
    this.appRedirectUri = 'bettercast://patreon/connected',
    this.userAgent = 'BetterCast/0.1 (+https://github.com/bettercast)',
    this.refreshInterval = const Duration(minutes: 20),
    this.allowRegistration = true,
  });

  final int port;
  final String databaseUrl;

  /// Public base URL of this server (used for the Patreon OAuth redirect).
  final String publicUrl;
  final String jwtSecret;

  /// 32-byte key (base64) used to encrypt private feed URLs and OAuth tokens.
  final List<int> encryptionKey;
  final String? podcastIndexKey;
  final String? podcastIndexSecret;
  final String? patreonClientId;
  final String? patreonClientSecret;

  /// Firebase service account JSON (content, not path) for FCM HTTP v1.
  final String? fcmServiceAccountJson;
  final String appRedirectUri;
  final String userAgent;
  final Duration refreshInterval;
  final bool allowRegistration;

  bool get podcastIndexEnabled =>
      podcastIndexKey != null && podcastIndexSecret != null;
  bool get patreonEnabled =>
      patreonClientId != null && patreonClientSecret != null;
  bool get fcmEnabled => fcmServiceAccountJson != null;

  String get patreonRedirectUri => '$publicUrl/patreon/oauth/callback';

  factory Config.fromEnv([Map<String, String>? env]) {
    final e = env ?? Platform.environment;
    String req(String k) {
      final v = e[k];
      if (v == null || v.isEmpty) {
        throw StateError('Missing required environment variable $k');
      }
      return v;
    }

    String? opt(String k) {
      final v = e[k];
      return v == null || v.trim().isEmpty ? null : v.trim();
    }

    final key = base64.decode(req('ENCRYPTION_KEY'));
    if (key.length != 32) {
      throw StateError('ENCRYPTION_KEY must be 32 bytes, base64-encoded '
          '(generate with: openssl rand -base64 32)');
    }
    final jwt = req('JWT_SECRET');
    if (jwt.length < 32) {
      throw StateError('JWT_SECRET must be at least 32 characters');
    }

    var fcm = opt('FCM_SERVICE_ACCOUNT_JSON');
    final fcmFile = opt('FCM_SERVICE_ACCOUNT_FILE');
    if (fcm == null && fcmFile != null && File(fcmFile).existsSync()) {
      fcm = File(fcmFile).readAsStringSync();
    }

    return Config(
      port: int.tryParse(e['PORT'] ?? '') ?? 8080,
      databaseUrl: req('DATABASE_URL'),
      publicUrl: req('PUBLIC_URL').replaceAll(RegExp(r'/+$'), ''),
      jwtSecret: jwt,
      encryptionKey: key,
      podcastIndexKey: opt('PODCAST_INDEX_KEY'),
      podcastIndexSecret: opt('PODCAST_INDEX_SECRET'),
      patreonClientId: opt('PATREON_CLIENT_ID'),
      patreonClientSecret: opt('PATREON_CLIENT_SECRET'),
      fcmServiceAccountJson: fcm,
      appRedirectUri: opt('APP_REDIRECT_URI') ?? 'bettercast://patreon/connected',
      refreshInterval: Duration(
          minutes: int.tryParse(e['REFRESH_INTERVAL_MINUTES'] ?? '') ?? 20),
      allowRegistration: (e['ALLOW_REGISTRATION'] ?? 'true') != 'false',
    );
  }
}
