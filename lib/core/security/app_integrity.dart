import 'package:flutter/services.dart';

/// What the runtime integrity check concluded.
enum IntegrityVerdict {
  /// The APK carries one of the certificates this build expects.
  trusted,

  /// The APK is signed by a certificate the build does not know, which is
  /// what a repackaged APK looks like: it had to be re-signed to install.
  untrusted,

  /// The platform could not answer, or the build expects no certificate.
  /// Never treated as tampering.
  unknown,
}

/// The outcome of [AppIntegrity.check].
class IntegrityReport {
  final IntegrityVerdict verdict;

  /// SHA-256 of every signing certificate of the installed APK, uppercase hex.
  final List<String> signers;

  /// How many certificates the APK is signed with. More than one means the
  /// APK carries a multi-signer signature.
  final int signerCount;

  /// Why the verdict is what it is.
  final String? reason;

  const IntegrityReport({
    required this.verdict,
    required this.signers,
    required this.signerCount,
    this.reason,
  });

  /// True only when the APK is demonstrably signed by someone else.
  bool get isRepackaged => verdict == IntegrityVerdict.untrusted;

  @override
  String toString() =>
      'IntegrityReport(${verdict.name}, signers: $signers, reason: $reason)';
}

/// Runtime self-integrity: compares the certificate the installed APK is
/// signed with against the certificates the build expects.
///
/// What this protects
/// ------------------
/// A repackaged APK has to be re-signed, because the original signature no
/// longer verifies once anything in the package is changed. The certificate
/// that signs it is therefore a different one, and the mismatch is visible on
/// the device. That turns "somebody patched the APK" from something invisible
/// into something the app can report.
///
/// What it does not protect
/// -----------------------
/// The expected fingerprints are compiled into the app, so an attacker who
/// patches the app can patch the comparison too. This raises the cost of
/// tampering; it does not make it impossible. Attestation that the attacker
/// cannot patch locally (Play Integrity, verified server-side) is the control
/// that actually holds, and it is deliberately left out until the app is
/// published on Play with a release key — see the plan in the repository
/// README.
///
/// Enforcement
/// ----------
/// Nothing here blocks the user. A verdict is data for the caller to record
/// and to act on; the app keeps working on an untrusted build, because bricking
/// the editor is a worse outcome for a legitimate user than a cracked copy
/// being alive.
class AppIntegrity {
  static const MethodChannel _channel = MethodChannel('bcode.integrity');

  /// SHA-256 fingerprints of the certificates this build accepts, comma
  /// separated, uppercase hex. Inject with
  /// `--dart-define=BCODE_CERT_SHA256=<hex>[,<hex>]`.
  static const String configuredCertificates = String.fromEnvironment(
    'BCODE_CERT_SHA256',
  );

  /// Parses [configuredCertificates] into a list of uppercase hex digests.
  static List<String> get expectedCertificates => _parse(configuredCertificates);

  /// Reads the signing certificates of the installed APK and compares them
  /// against [expected], or against [expectedCertificates] when no list is
  /// given.
  static Future<IntegrityReport> check({List<String>? expected}) async {
    final wanted = expected != null
        ? _parse(expected.join(','))
        : expectedCertificates;

    final Map<Object?, Object?>? reply;
    try {
      reply = await _channel.invokeMapMethod<Object?, Object?>(
        'signingCertificates',
      );
    } on PlatformException catch (e) {
      return IntegrityReport(
        verdict: IntegrityVerdict.unknown,
        signers: const [],
        signerCount: 0,
        reason: e.message ?? 'the platform could not report the signer',
      );
    } on MissingPluginException {
      return IntegrityReport(
        verdict: IntegrityVerdict.unknown,
        signers: const [],
        signerCount: 0,
        reason: 'the integrity channel is not available on this build',
      );
    }

    final signers = (reply?['signers'] as List?)
            ?.map((e) => '$e'.trim().toUpperCase())
            .where((e) => e.isNotEmpty)
            .toList() ??
        const <String>[];
    final signerCount = (reply?['signerCount'] as num?)?.toInt() ?? signers.length;

    if (signers.isEmpty) {
      return IntegrityReport(
        verdict: IntegrityVerdict.unknown,
        signers: signers,
        signerCount: signerCount,
        reason: 'the installed package reports no signing certificate',
      );
    }
    if (wanted.isEmpty) {
      return IntegrityReport(
        verdict: IntegrityVerdict.unknown,
        signers: signers,
        signerCount: signerCount,
        reason: 'this build expects no signing certificate',
      );
    }

    final matched = signers.any(wanted.contains);
    return IntegrityReport(
      verdict: matched ? IntegrityVerdict.trusted : IntegrityVerdict.untrusted,
      signers: signers,
      signerCount: signerCount,
      reason: matched
          ? null
          : 'the APK is signed by ${signers.join(", ")}, which this build '
                'does not expect',
    );
  }

  static List<String> _parse(String value) => value
      .split(',')
      .map((e) => e.trim().toUpperCase())
      .where((e) => e.isNotEmpty)
      .toList();
}
