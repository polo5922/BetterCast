import 'dart:convert';

import 'package:bettercast_server/bettercast_server.dart';
import 'package:bettercast_server/src/http/rate_limiter.dart';
import 'package:test/test.dart';

void main() {
  group('PasswordHasher', () {
    final hasher = PasswordHasher();

    test('verifies the right password only', () async {
      final hash = await hasher.hash('correct horse battery staple');
      expect(hash, startsWith(r'$argon2id$'));
      expect(await hasher.verify('correct horse battery staple', hash), isTrue);
      expect(await hasher.verify('wrong', hash), isFalse);
    });

    test('salts every hash', () async {
      expect(await hasher.hash('pw'), isNot(await hasher.hash('pw')));
    });
  });

  group('Encryptor', () {
    final key = List<int>.generate(32, (i) => i);

    test('round-trips and uses a fresh nonce', () async {
      final e = Encryptor(key);
      const secret = 'https://www.patreon.com/rss/creator?auth=abc123';
      final a = await e.encrypt(secret);
      final b = await e.encrypt(secret);
      expect(a, isNot(b));
      expect(await e.decrypt(a), secret);
    });

    test('rejects tampered ciphertext', () async {
      final e = Encryptor(key);
      final bytes = base64Decode(await e.encrypt('secret'));
      bytes[bytes.length ~/ 2] ^= 0xff;
      expect(() => e.decrypt(base64Encode(bytes)), throwsA(anything));
    });
  });

  test('RateLimiter blocks past the budget', () {
    final l = RateLimiter(maxHits: 3, window: const Duration(minutes: 1));
    expect([for (var i = 0; i < 4; i++) l.hit('ip')], [true, true, true, false]);
    expect(l.hit('other'), isTrue);
  });

  test('sha256Hex is stable', () {
    expect(sha256Hex('abc'),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
  });
}
