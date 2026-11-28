import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';

/// Whether the BetterCast server is reachable.
///
/// The OS link state alone is not enough (a Wi-Fi without Internet still
/// counts as "connected"), so it is confirmed by a ping to `/health`. API
/// calls failing with a network error also flip it to offline; while
/// offline the server is pinged again every 30 s.
class OnlineNotifier extends Notifier<bool> {
  StreamSubscription<List<ConnectivityResult>>? _sub;
  Timer? _retry;
  bool _hasLink = true;
  bool _probing = false;

  @override
  bool build() {
    _sub = Connectivity().onConnectivityChanged.listen(_onLink, onError: (_) {});
    unawaited(Connectivity().checkConnectivity().then(_onLink, onError: (_) {}));
    ref.onDispose(() {
      _sub?.cancel();
      _retry?.cancel();
    });
    return true;
  }

  void _onLink(List<ConnectivityResult> r) {
    _hasLink = r.any((c) => c != ConnectivityResult.none);
    if (!_hasLink) {
      _set(false);
    } else {
      unawaited(probe());
    }
  }

  /// Called when a request failed for lack of network.
  void reportOffline() {
    if (!state) return;
    _set(false);
  }

  /// Called when a request succeeded.
  void reportOnline() => _set(true);

  Future<void> probe() async {
    if (_probing) return;
    final server = ref.read(tokenStoreProvider).serverUrl;
    if (server == null || server.isEmpty) return _set(_hasLink);
    _probing = true;
    try {
      await Dio(BaseOptions(
        baseUrl: server,
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 5),
      )).get<dynamic>('/health');
      _set(true);
    } on DioException catch (e) {
      // Any HTTP answer means the server is reachable.
      _set(e.response != null);
    } finally {
      _probing = false;
    }
  }

  void _set(bool online) {
    _retry?.cancel();
    _retry = online
        ? null
        : Timer.periodic(const Duration(seconds: 30), (_) {
            if (_hasLink) unawaited(probe());
          });
    if (state != online) state = online;
  }
}

final onlineProvider = NotifierProvider<OnlineNotifier, bool>(OnlineNotifier.new);
