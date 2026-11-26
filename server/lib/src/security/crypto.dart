import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' as hash;
import 'package:cryptography/cryptography.dart' as c;

final _rng = Random.secure();

List<int> randomBytes(int n) => List<int>.generate(n, (_) => _rng.nextInt(256));

String randomToken([int bytes = 32]) =>
    base64Url.encode(randomBytes(bytes)).replaceAll('=', '');

String sha256Hex(String v) => hash.sha256.convert(utf8.encode(v)).toString();

/// Argon2id password hashing (OWASP parameters: m=19 MiB, t=2, p=1),
/// stored in the PHC string format.
class PasswordHasher {
  PasswordHasher({this.memoryKib = 19456, this.iterations = 2});

  final int memoryKib;
  final int iterations;

  c.Argon2id _algo(int m, int t) =>
      c.Argon2id(parallelism: 1, memory: m, iterations: t, hashLength: 32);

  Future<String> hash(String password) async {
    final salt = randomBytes(16);
    final key = await _algo(memoryKib, iterations)
        .deriveKeyFromPassword(password: password, nonce: salt);
    final bytes = await key.extractBytes();
    return '\$argon2id\$v=19\$m=$memoryKib,t=$iterations,p=1'
        '\$${_b64(salt)}\$${_b64(bytes)}';
  }

  Future<bool> verify(String password, String encoded) async {
    final parts = encoded.split('\$');
    // ['', 'argon2id', 'v=19', 'm=..,t=..,p=..', salt, hash]
    if (parts.length != 6 || parts[1] != 'argon2id') return false;
    final params = {
      for (final kv in parts[3].split(','))
        kv.split('=')[0]: int.tryParse(kv.split('=')[1]) ?? 0,
    };
    final salt = _unb64(parts[4]);
    final expected = _unb64(parts[5]);
    final key = await _algo(params['m'] ?? memoryKib, params['t'] ?? iterations)
        .deriveKeyFromPassword(password: password, nonce: salt);
    final actual = await key.extractBytes();
    return _constantTimeEquals(actual, expected);
  }

  static String _b64(List<int> b) => base64.encode(b).replaceAll('=', '');
  static List<int> _unb64(String s) =>
      base64.decode(s.padRight((s.length + 3) ~/ 4 * 4, '='));
}

bool _constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var r = 0;
  for (var i = 0; i < a.length; i++) {
    r |= a[i] ^ b[i];
  }
  return r == 0;
}

/// AES-256-GCM encryption for secrets at rest (private feed URLs, OAuth
/// tokens). Output: base64(nonce | ciphertext | mac).
class Encryptor {
  Encryptor(List<int> key) : _key = c.SecretKey(key);

  final c.SecretKey _key;
  final _algo = c.AesGcm.with256bits();

  Future<String> encrypt(String plain) async {
    final box = await _algo.encrypt(utf8.encode(plain), secretKey: _key);
    return base64.encode(box.concatenation());
  }

  Future<String> decrypt(String encoded) async {
    final box = c.SecretBox.fromConcatenation(
      base64.decode(encoded),
      nonceLength: _algo.nonceLength,
      macLength: _algo.macAlgorithm.macLength,
    );
    return utf8.decode(await _algo.decrypt(box, secretKey: _key));
  }
}
