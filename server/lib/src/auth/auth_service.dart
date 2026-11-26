import 'package:bettercast_core/bettercast_core.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:postgres/postgres.dart';
import 'package:shelf/shelf.dart';

import '../http/json.dart';
import '../security/crypto.dart';

const accessTokenTtl = Duration(minutes: 15);
const refreshTokenTtl = Duration(days: 60);

class AuthService {
  AuthService(this._db, String jwtSecret, {PasswordHasher? hasher})
      : _key = SecretKey(jwtSecret),
        _hasher = hasher ?? PasswordHasher();

  final Pool _db;
  final SecretKey _key;
  final PasswordHasher _hasher;

  static final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  Future<AuthResponse> register(
    String email,
    String password, {
    String? displayName,
  }) async {
    email = email.trim().toLowerCase();
    if (!_emailRe.hasMatch(email)) throw ApiException.badRequest('Invalid email');
    if (password.length < 8) {
      throw ApiException.badRequest('Password must be at least 8 characters');
    }
    final hash = await _hasher.hash(password);
    final Result rows;
    try {
      rows = await _db.execute(
        Sql.named('INSERT INTO users(email, password_hash, display_name) '
            'VALUES (@e, @h, @n) RETURNING id::text'),
        parameters: {'e': email, 'h': hash, 'n': displayName},
      );
    } on ServerException catch (e) {
      if (e.code == '23505') throw ApiException.conflict('Email already used');
      rethrow;
    }
    final user = UserProfile(
      id: rows.first[0] as String,
      email: email,
      displayName: displayName,
    );
    return AuthResponse(user: user, tokens: await _issue(user.id));
  }

  Future<AuthResponse> login(String email, String password) async {
    email = email.trim().toLowerCase();
    final rows = await _db.execute(
      Sql.named('SELECT id::text, password_hash FROM users WHERE email = @e'),
      parameters: {'e': email},
    );
    if (rows.isEmpty) {
      // Same cost as a real check, to avoid leaking which emails exist.
      await _hasher.hash(password);
      throw ApiException(401, 'invalid_credentials', 'Wrong email or password');
    }
    final ok = await _hasher.verify(password, rows.first[1] as String);
    if (!ok) {
      throw ApiException(401, 'invalid_credentials', 'Wrong email or password');
    }
    final id = rows.first[0] as String;
    return AuthResponse(user: await profile(id), tokens: await _issue(id));
  }

  /// Rotates a refresh token: the old one is revoked, a new pair is issued.
  Future<AuthTokens> refresh(String refreshToken) async {
    final rows = await _db.execute(
      Sql.named('UPDATE refresh_tokens SET revoked_at = now() '
          'WHERE token_hash = @h AND revoked_at IS NULL AND expires_at > now() '
          'RETURNING user_id::text'),
      parameters: {'h': sha256Hex(refreshToken)},
    );
    if (rows.isEmpty) {
      throw ApiException(401, 'invalid_refresh_token', 'Session expired');
    }
    return _issue(rows.first[0] as String);
  }

  Future<void> logout(String refreshToken) => _db.execute(
        Sql.named('UPDATE refresh_tokens SET revoked_at = now() '
            'WHERE token_hash = @h'),
        parameters: {'h': sha256Hex(refreshToken)},
      );

  Future<UserProfile> profile(String userId) async {
    final rows = await _db.execute(
      Sql.named('SELECT u.email, u.display_name, '
          '(SELECT count(*) FROM patreon_accounts p WHERE p.user_id = u.id) > 0 '
          'FROM users u WHERE u.id = @id::uuid'),
      parameters: {'id': userId},
    );
    if (rows.isEmpty) throw ApiException.unauthorized();
    final r = rows.first;
    return UserProfile(
      id: userId,
      email: r[0] as String,
      displayName: r[1] as String?,
      patreonConnected: r[2] as bool,
    );
  }

  Future<AuthTokens> _issue(String userId) async {
    final expiresAt = DateTime.now().toUtc().add(accessTokenTtl);
    final access = JWT({'sub': userId, 'typ': 'access'})
        .sign(_key, expiresIn: accessTokenTtl);
    final refresh = randomToken(32);
    await _db.execute(
      Sql.named('INSERT INTO refresh_tokens(token_hash, user_id, expires_at) '
          'VALUES (@h, @u::uuid, @x)'),
      parameters: {
        'h': sha256Hex(refresh),
        'u': userId,
        'x': DateTime.now().toUtc().add(refreshTokenTtl),
      },
    );
    return AuthTokens(
      accessToken: access,
      refreshToken: refresh,
      expiresAt: expiresAt,
    );
  }

  /// Returns the user id of a valid access token, or null.
  String? verifyAccessToken(String token) {
    try {
      final jwt = JWT.verify(token, _key);
      final payload = jwt.payload;
      if (payload is Map && payload['typ'] == 'access') {
        return payload['sub'] as String?;
      }
    } on JWTException {
      return null;
    }
    return null;
  }

  /// Middleware putting the authenticated user id in `request.context['userId']`.
  Middleware middleware() => (inner) => (req) {
        final header = req.headers['authorization'];
        if (header == null || !header.startsWith('Bearer ')) {
          throw ApiException.unauthorized();
        }
        final userId = verifyAccessToken(header.substring(7));
        if (userId == null) {
          throw ApiException(401, 'token_expired', 'Access token expired');
        }
        return inner(req.change(context: {'userId': userId}));
      };
}

extension AuthRequest on Request {
  String get userId => context['userId']! as String;
}
