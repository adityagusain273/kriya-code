import 'package:shared_preferences/shared_preferences.dart';

class Entitlements {
  final bool proTier;
  final Set<String> unlockedRuntimes;
  final Set<String> unlockedExtensions;

  const Entitlements({
    required this.proTier,
    this.unlockedRuntimes = const {},
    this.unlockedExtensions = const {},
  });

  static const free = Entitlements(proTier: false);
}

abstract class EntitlementService {
  Future<Entitlements> current();
  bool isRuntimeUnlocked(String runtimeId);
  Future<void> unlockRuntime(String runtimeId);
  bool isExtensionUnlocked(String extensionId);
  Future<void> unlockExtension(String extensionId);
  Future<void> setProTier(bool isPro);
}

class LocalEntitlementService implements EntitlementService {
  static const _unlockedRuntimesKey = 'bcode_unlocked_runtimes';
  static const _unlockedExtensionsKey = 'bcode_unlocked_extensions';
  static const _proTierKey = 'bcode_pro_tier';

  final SharedPreferences _prefs;
  final Set<String> _unlockedRuntimes;
  final Set<String> _unlockedExtensions;
  bool _isPro;

  LocalEntitlementService(this._prefs)
      : _unlockedRuntimes = (_prefs.getStringList(_unlockedRuntimesKey) ?? <String>[]).toSet(),
        _unlockedExtensions = (_prefs.getStringList(_unlockedExtensionsKey) ?? <String>[]).toSet(),
        _isPro = _prefs.getBool(_proTierKey) ?? false;

  @override
  Future<Entitlements> current() async {
    return Entitlements(
      proTier: _isPro,
      unlockedRuntimes: Set.unmodifiable(_unlockedRuntimes),
      unlockedExtensions: Set.unmodifiable(_unlockedExtensions),
    );
  }

  @override
  bool isRuntimeUnlocked(String runtimeId) {
    if (_isPro) return true;
    return _unlockedRuntimes.contains(runtimeId);
  }

  @override
  Future<void> unlockRuntime(String runtimeId) async {
    if (_unlockedRuntimes.add(runtimeId)) {
      await _prefs.setStringList(_unlockedRuntimesKey, _unlockedRuntimes.toList());
    }
  }

  @override
  bool isExtensionUnlocked(String extensionId) {
    if (_isPro) return true;
    return _unlockedExtensions.contains(extensionId);
  }

  @override
  Future<void> unlockExtension(String extensionId) async {
    if (_unlockedExtensions.add(extensionId)) {
      await _prefs.setStringList(_unlockedExtensionsKey, _unlockedExtensions.toList());
    }
  }

  @override
  Future<void> setProTier(bool isPro) async {
    _isPro = isPro;
    await _prefs.setBool(_proTierKey, isPro);
  }
}
