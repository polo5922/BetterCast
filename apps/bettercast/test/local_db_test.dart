import 'package:bettercast/core/local_db.dart';
import 'package:bettercast/core/providers.dart';
import 'package:bettercast_core/bettercast_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late LocalDb db;
  setUp(() => db = LocalDb.inMemory());
  tearDown(() => db.close());

  EpisodeState st(int sec, DateTime at, {bool liked = false}) => EpisodeState(
      episodeId: 'e1', podcastId: 'p1', position: Duration(seconds: sec), liked: liked, updatedAt: at);

  test('saveState keeps the most recent write (LWW)', () {
    final t0 = DateTime.utc(2026, 1, 1);
    db.saveState(st(100, t0.add(const Duration(minutes: 5)), liked: true), dirty: true);
    db.saveState(st(10, t0), dirty: false); // older server copy: ignored
    final s = db.allStates()['e1']!;
    expect(s.position, const Duration(seconds: 100));
    expect(s.liked, isTrue);
    expect(db.dirtyStates(), hasLength(1));
  });

  test('markClean clears the dirty flag', () {
    final s = st(5, DateTime.utc(2026, 1, 2));
    db.saveState(s, dirty: true);
    db.markClean([s]);
    expect(db.dirtyStates(), isEmpty);
  });

  test('cache and kv round-trip', () {
    db.putCache('k', {'a': 1});
    expect(db.getCache('k'), {'a': 1});
    db.setKv('since', '2026');
    expect(db.getKv('since'), '2026');
    db.setKv('since', null);
    expect(db.getKv('since'), isNull);
  });

  test('normalizeServerUrl', () {
    expect(normalizeServerUrl(' pods.example.org/ '), 'https://pods.example.org');
    expect(normalizeServerUrl('http://localhost:8080//'), 'http://localhost:8080');
  });
}
