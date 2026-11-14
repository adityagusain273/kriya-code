import 'package:shared_preferences/shared_preferences.dart';

class Entitlements {
  final bool proTier;
  final Set<String> unlockedRuntimes;

  const Entitlements({
    required this.proTier,
    this.unlockedRuntimes = const {},
  });

  static const free = Entitlements(proTier: false);
}

abstract class EntitlementService {
  Future<Entitlements> current();
  bool isRuntimeUnlocked(String runtimeId);
  Future<void> unlockRuntime(String runtimeId);
  Future<void> setProTier(bool isPro);
}

class LocalEntitlementService implements EntitlementService {
  static const _unlockedRuntimesKey = 'bcode_unlocked_runtimes';
  static const _proTierKey = 'bcode_pro_tier';

  final SharedPreferences _prefs;
  final Set<String> _unlocked;
  bool _isPro;

  LocalEntitlementService(this._prefs)
      : _unlocked = (_prefs.getStringList(_unlockedRuntimesKey) ?? <String>[]).toSet(),
        _isPro = _prefs.getBool(_proTierKey) ?? false;

  @override
  Future<Entitlements> current() async {
    return Entitlements(
      proTier: _isPro,
      unlockedRuntimes: Set.unmodifiable(_unlocked),
    );
  }

  @override
  bool isRuntimeUnlocked(String runtimeId) {
    if (_isPro) return true;
    return _unlocked.contains(runtimeId);
  }

  @override
  Future<void> unlockRuntime(String runtimeId) async {
    if (_unlocked.add(runtimeId)) {
      await _prefs.setStringList(_unlockedRuntimesKey, _unlocked.toList());
    }
  }

  @override
  Future<void> setProTier(bool isPro) async {
    _isPro = isPro;
    await _prefs.setBool(_proTierKey, isPro);
  }
}
