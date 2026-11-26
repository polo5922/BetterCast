/// Fixed-window in-memory rate limiter (per key, e.g. client IP).
class RateLimiter {
  RateLimiter({required this.maxHits, required this.window});

  final int maxHits;
  final Duration window;
  final _hits = <String, (DateTime, int)>{};

  /// Records a hit; returns false when the key is over its budget.
  bool hit(String key) {
    final now = DateTime.now();
    if (_hits.length > 10000) {
      _hits.removeWhere((_, v) => now.difference(v.$1) > window);
    }
    final cur = _hits[key];
    if (cur == null || now.difference(cur.$1) > window) {
      _hits[key] = (now, 1);
      return true;
    }
    _hits[key] = (cur.$1, cur.$2 + 1);
    return cur.$2 + 1 <= maxHits;
  }
}
