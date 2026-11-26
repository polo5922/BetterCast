import 'dart:convert';

import 'package:bettercast_core/bettercast_core.dart';
import 'package:http/http.dart' as http;
import 'package:postgres/postgres.dart';

import '../config.dart';
import '../feeds/podcast_repository.dart';
import '../http/json.dart';
import '../security/crypto.dart';

/// Patreon OAuth2 (server side: the client secret never reaches the app)
/// and membership listing. Episodes come from each creator's private RSS feed
/// that the user links to a campaign.
class PatreonService {
  PatreonService(this._db, this._config, this._crypto, this._podcasts,
      {http.Client? client})
      : _client = client ?? http.Client();

  final Pool _db;
  final Config _config;
  final Encryptor _crypto;
  final PodcastRepository _podcasts;
  final http.Client _client;

  static const _authorize = 'https://www.patreon.com/oauth2/authorize';
  static const _token = 'https://www.patreon.com/api/oauth2/token';
  static const _api = 'https://www.patreon.com/api/oauth2/v2';

  void _ensureEnabled() {
    if (!_config.patreonEnabled) {
      throw ApiException(503, 'patreon_disabled',
          'Patreon is not configured on this server');
    }
  }

  Future<Uri> authorizeUrl(String userId) async {
    _ensureEnabled();
    final state = randomToken(24);
    await _db.execute(
      Sql.named('DELETE FROM oauth_states WHERE created_at < now() - interval \'1 hour\''),
    );
    await _db.execute(
      Sql.named('INSERT INTO oauth_states(state, user_id) VALUES (@s, @u::uuid)'),
      parameters: {'s': state, 'u': userId},
    );
    return Uri.parse(_authorize).replace(queryParameters: {
      'response_type': 'code',
      'client_id': _config.patreonClientId,
      'redirect_uri': _config.patreonRedirectUri,
      'scope': 'identity identity.memberships',
      'state': state,
    });
  }

  /// Handles the OAuth redirect. Returns the BetterCast user id.
  Future<String> handleCallback({required String code, required String state}) async {
    _ensureEnabled();
    final rows = await _db.execute(
      Sql.named('DELETE FROM oauth_states WHERE state = @s '
          'AND created_at > now() - interval \'15 minutes\' RETURNING user_id::text'),
      parameters: {'s': state},
    );
    if (rows.isEmpty) throw ApiException.badRequest('Invalid or expired state');
    final userId = rows.first[0] as String;

    final tokens = await _tokenRequest({
      'grant_type': 'authorization_code',
      'code': code,
      'redirect_uri': _config.patreonRedirectUri,
    });
    final identity = await _get('/identity', tokens.access, {});
    final patreonUserId = (identity['data'] as Map)['id'] as String;
    await _saveTokens(userId, patreonUserId, tokens);
    await syncMemberships(userId);
    return userId;
  }

  Future<List<PatreonCampaign>> syncMemberships(String userId) async {
    _ensureEnabled();
    final access = await _accessToken(userId);
    final j = await _get('/identity', access, {
      'include': 'memberships.campaign,memberships.currently_entitled_tiers',
      'fields[member]': 'patron_status',
      'fields[campaign]': 'creation_name,vanity,url,image_url,image_small_url',
      'fields[tier]': 'title',
    });

    final included = (j['included'] as List? ?? []).whereType<Map>().toList();
    Map<String, Map> byType(String t) => {
          for (final i in included)
            if (i['type'] == t) i['id'] as String: i,
        };
    final campaigns = byType('campaign');
    final tiers = byType('tier');

    final found = <PatreonCampaign>[];
    for (final m in byType('member').values) {
      final rel = (m['relationships'] as Map?) ?? {};
      final campaignId =
          ((rel['campaign'] as Map?)?['data'] as Map?)?['id'] as String?;
      final c = campaigns[campaignId];
      if (campaignId == null || c == null) continue;
      final attrs = (c['attributes'] as Map?) ?? {};
      final tierIds = [
        for (final t
            in ((rel['currently_entitled_tiers'] as Map?)?['data'] as List? ?? [])
                .whereType<Map>())
          t['id'] as String,
      ];
      final tierTitle = tierIds
          .map((id) => (tiers[id]?['attributes'] as Map?)?['title'] as String?)
          .whereType<String>()
          .join(', ');
      found.add(PatreonCampaign(
        id: campaignId,
        name: (attrs['creation_name'] as String?)?.trim().isNotEmpty == true
            ? attrs['creation_name'] as String
            : (attrs['vanity'] as String?) ?? 'Patreon $campaignId',
        imageUrl: attrs['image_small_url'] as String? ?? attrs['image_url'] as String?,
        url: attrs['url'] as String?,
        tierTitle: tierTitle.isEmpty ? null : tierTitle,
      ));
    }

    await _db.runTx((tx) async {
      for (final c in found) {
        await tx.execute(
          Sql.named('INSERT INTO patreon_campaigns(user_id, campaign_id, name, '
              'image_url, url, tier_title) VALUES (@u::uuid, @c, @n, @i, @url, @t) '
              'ON CONFLICT (user_id, campaign_id) DO UPDATE SET name = EXCLUDED.name, '
              'image_url = EXCLUDED.image_url, url = EXCLUDED.url, '
              'tier_title = EXCLUDED.tier_title, updated_at = now()'),
          parameters: {
            'u': userId,
            'c': c.id,
            'n': c.name,
            'i': c.imageUrl,
            'url': c.url,
            't': c.tierTitle,
          },
        );
      }
      // Memberships that ended: drop them unless a feed is still linked.
      await tx.execute(
        Sql.named('DELETE FROM patreon_campaigns WHERE user_id = @u::uuid '
            'AND podcast_id IS NULL AND NOT (campaign_id = ANY(@ids))'),
        parameters: {
          'u': userId,
          'ids': TypedValue(Type.textArray, [for (final c in found) c.id]),
        },
      );
    });
    return campaignsOf(userId);
  }

  Future<List<PatreonCampaign>> campaignsOf(String userId) async {
    final rows = await _db.execute(
      Sql.named('SELECT campaign_id, name, image_url, url, tier_title, podcast_id '
          'FROM patreon_campaigns WHERE user_id = @u::uuid ORDER BY name'),
      parameters: {'u': userId},
    );
    return [
      for (final r in rows)
        PatreonCampaign(
          id: r[0] as String,
          name: r[1] as String,
          imageUrl: r[2] as String?,
          url: r[3] as String?,
          tierTitle: r[4] as String?,
          podcastId: r[5] as String?,
        ),
    ];
  }

  /// Links a creator's private RSS feed (the "Get audio RSS link" URL from
  /// Patreon) to a campaign, and subscribes the user to it.
  Future<Podcast> linkFeed(String userId, String campaignId, String feedUrl) async {
    final uri = Uri.tryParse(feedUrl.trim());
    if (uri == null || uri.scheme != 'https' || !uri.host.endsWith('patreon.com')) {
      throw ApiException.badRequest('Expected a https://www.patreon.com/rss/... link');
    }
    final rows = await _db.execute(
      Sql.named('SELECT podcast_id FROM patreon_campaigns '
          'WHERE user_id = @u::uuid AND campaign_id = @c'),
      parameters: {'u': userId, 'c': campaignId},
    );
    if (rows.isEmpty) throw ApiException.notFound('Unknown campaign');
    final podcast = await _podcasts.upsertPrivate(
      userId: userId,
      feedUrl: uri.toString(),
      source: PodcastSource.patreon,
      existingId: rows.first[0] as String?,
    );
    await _db.execute(
      Sql.named('UPDATE patreon_campaigns SET podcast_id = @p, updated_at = now() '
          'WHERE user_id = @u::uuid AND campaign_id = @c'),
      parameters: {'p': podcast.id, 'u': userId, 'c': campaignId},
    );
    await _db.execute(
      Sql.named('INSERT INTO subscriptions(user_id, podcast_id) VALUES (@u::uuid, @p) '
          'ON CONFLICT DO NOTHING'),
      parameters: {'u': userId, 'p': podcast.id},
    );
    return podcast;
  }

  Future<void> disconnect(String userId) async {
    await _db.execute(
      Sql.named('DELETE FROM patreon_accounts WHERE user_id = @u::uuid'),
      parameters: {'u': userId},
    );
    await _db.execute(
      Sql.named('DELETE FROM patreon_campaigns WHERE user_id = @u::uuid '
          'AND podcast_id IS NULL'),
      parameters: {'u': userId},
    );
  }

  // ---- token handling ----------------------------------------------------

  Future<String> _accessToken(String userId) async {
    final rows = await _db.execute(
      Sql.named('SELECT patreon_user_id, access_token_enc, refresh_token_enc, '
          'expires_at FROM patreon_accounts WHERE user_id = @u::uuid'),
      parameters: {'u': userId},
    );
    if (rows.isEmpty) {
      throw ApiException(409, 'patreon_not_connected', 'Connect Patreon first');
    }
    final r = rows.first;
    final expiresAt = r[3] as DateTime;
    if (expiresAt.isAfter(DateTime.now().add(const Duration(minutes: 5)))) {
      return _crypto.decrypt(r[1] as String);
    }
    final tokens = await _tokenRequest({
      'grant_type': 'refresh_token',
      'refresh_token': await _crypto.decrypt(r[2] as String),
    });
    await _saveTokens(userId, r[0] as String, tokens);
    return tokens.access;
  }

  Future<void> _saveTokens(String userId, String patreonUserId, _Tokens t) async {
    await _db.execute(
      Sql.named('INSERT INTO patreon_accounts(user_id, patreon_user_id, '
          'access_token_enc, refresh_token_enc, expires_at) '
          'VALUES (@u::uuid, @p, @a, @r, @x) ON CONFLICT (user_id) DO UPDATE SET '
          'patreon_user_id = EXCLUDED.patreon_user_id, '
          'access_token_enc = EXCLUDED.access_token_enc, '
          'refresh_token_enc = EXCLUDED.refresh_token_enc, '
          'expires_at = EXCLUDED.expires_at, updated_at = now()'),
      parameters: {
        'u': userId,
        'p': patreonUserId,
        'a': await _crypto.encrypt(t.access),
        'r': await _crypto.encrypt(t.refresh),
        'x': DateTime.now().toUtc().add(t.expiresIn),
      },
    );
  }

  Future<_Tokens> _tokenRequest(Map<String, String> form) async {
    final res = await _client.post(Uri.parse(_token), body: {
      ...form,
      'client_id': _config.patreonClientId!,
      'client_secret': _config.patreonClientSecret!,
    }).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw ApiException(502, 'patreon_error', 'Patreon token error ${res.statusCode}');
    }
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    return _Tokens(
      j['access_token'] as String,
      j['refresh_token'] as String,
      Duration(seconds: (j['expires_in'] as num?)?.toInt() ?? 2678400),
    );
  }

  Future<Map<String, dynamic>> _get(
    String path,
    String access,
    Map<String, String> query,
  ) async {
    final res = await _client.get(
      Uri.parse('$_api$path').replace(queryParameters: query.isEmpty ? null : query),
      headers: {
        'Authorization': 'Bearer $access',
        'User-Agent': _config.userAgent,
      },
    ).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw ApiException(502, 'patreon_error', 'Patreon API error ${res.statusCode}');
    }
    return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  }
}

class _Tokens {
  _Tokens(this.access, this.refresh, this.expiresIn);
  final String access;
  final String refresh;
  final Duration expiresIn;
}
