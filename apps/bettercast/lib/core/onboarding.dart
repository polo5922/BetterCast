import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';

/// Whether the signed-in user went through the welcome flow (per user,
/// stored on this device).
class OnboardingNotifier extends Notifier<bool> {
  String get _key => 'onboarding_${ref.read(sessionProvider).user?.id ?? ''}';

  @override
  bool build() {
    ref.watch(sessionProvider.select((s) => s.user?.id));
    return ref.read(localDbProvider).getKv(_key) == '1';
  }

  void complete() {
    ref.read(localDbProvider).setKv(_key, '1');
    state = true;
  }

  /// "Revoir la présentation" in the settings.
  void replay() {
    ref.read(localDbProvider).setKv(_key, null);
    state = false;
  }
}

final onboardingDoneProvider =
    NotifierProvider<OnboardingNotifier, bool>(OnboardingNotifier.new);
