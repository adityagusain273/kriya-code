import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'device_id_provider.dart';
import 'license_service.dart';

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
  /// Re-derives the Pro tier from the stored license key. Must run before the
  /// first frame, because [isRuntimeUnlocked] is synchronous.
  Future<void> restore();

  Future<Entitlements> current();
  bool isRuntimeUnlocked(String runtimeId);
  Future<void> unlockRuntime(String runtimeId);
  bool isExtensionUnlocked(String extensionId);
  Future<void> unlockExtension(String extensionId);
  Future<void> setProTier(bool isPro);
  Future<LicenseValidationResult> activateWithLicenseKey(String licenseKey);
}

class LocalEntitlementService implements EntitlementService {
  static const _unlockedRuntimesKey = 'bcode_unlocked_runtimes';
  static const _unlockedExtensionsKey = 'bcode_unlocked_extensions';
  static const _licenseKeyPref = 'bcode_license_key';

  /// Written by releases up to 1.0.0+10, which trusted this flag as proof of
  /// purchase. Deleted on restore; it is never read.
  static const _legacyProTierKey = 'bcode_pro_tier';

  final SharedPreferences _prefs;
  final FlutterSecureStorage _secureStorage;
  final LicenseVerifier _verifier;
  final Set<String> _unlockedRuntimes;
  final Set<String> _unlockedExtensions;
  bool _isPro = false;
  Future<void>? _restore;

  LocalEntitlementService(
    this._prefs, {
    FlutterSecureStorage? secureStorage,
    LicenseVerifier? verifier,
  })  : _secureStorage = secureStorage ?? const FlutterSecureStorage(),
        _verifier = verifier ?? LicenseVerifier(),
        _unlockedRuntimes = (_prefs.getStringList(_unlockedRuntimesKey) ?? <String>[]).toSet(),
        _unlockedExtensions = (_prefs.getStringList(_unlockedExtensionsKey) ?? <String>[]).toSet();

  /// Pro is a property of a signature this app can check, never of a stored
  /// boolean: anyone who can edit app data could otherwise flip a preference
  /// and own every paid feature. The key lands in secure storage, and its
  /// signature is re-verified here on every launch.
  @override
  Future<void> restore() => _restore ??= _doRestore();

  Future<void> _doRestore() async {
    await _prefs.remove(_legacyProTierKey);

    String? key;
    try {
      key = await _secureStorage.read(key: _licenseKeyPref);
    } catch (_) {
      // Secure storage unavailable (tests, or a device whose keystore was
      // reset); fall through to the legacy plaintext copy below.
    }
    final legacy = _prefs.getString(_licenseKeyPref);
    if (legacy != null && legacy.isNotEmpty) {
      if (key == null) {
        key = legacy;
      } else {
        // The secure copy won; drop the plaintext one.
        await _prefs.remove(_licenseKeyPref);
      }
    }
    if (key == null || key.isEmpty) return;

    final result = _verifier.validate(
      key,
      currentDeviceId: await DeviceIdProvider.getDeviceId(),
    );
    _isPro = result.isValid;
  }

  @override
  Future<Entitlements> current() async {
    await restore();
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
    // Granting Pro is only possible through [activateWithLicenseKey]; accepting
    // it from a caller would put the gate back in client-controlled hands.
    if (isPro) return;
    _isPro = false;
    await _prefs.remove(_licenseKeyPref);
    await _prefs.remove(_legacyProTierKey);
    try {
      await _secureStorage.delete(key: _licenseKeyPref);
    } catch (_) {}
  }

  @override
  Future<LicenseValidationResult> activateWithLicenseKey(String licenseKey) async {
    final currentDevice = await DeviceIdProvider.getDeviceId();
    final result = _verifier.validate(licenseKey, currentDeviceId: currentDevice);
    if (!result.isValid) return result;

    final clean = licenseKey.trim();
    _isPro = true;
    await _prefs.remove(_legacyProTierKey);
    try {
      await _secureStorage.write(key: _licenseKeyPref, value: clean);
      await _prefs.remove(_licenseKeyPref);
    } catch (_) {
      // No keystore on this device: keep the key in prefs so a paid licence
      // still survives a restart. The signature is what unlocks Pro.
      await _prefs.setString(_licenseKeyPref, clean);
    }
    return result;
  }
}
