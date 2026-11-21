import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
/// Enforceable in release builds when a certificate is configured. If repackaging
/// is detected, a blocking/warning dialog is displayed on app launch. Debug
/// builds and unconfigured builds remain unaffected.
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

  /// Whether repackaging detection is enforceable on this build:
  /// true only in release mode when a certificate is configured.
  static bool get isEnforceable => isEnforceableBuild();

  /// Helper to evaluate enforceability across release modes and certificate sets.
  static bool isEnforceableBuild({
    bool releaseMode = kReleaseMode,
    List<String>? expected,
  }) {
    final certs = expected != null
        ? _parse(expected.join(','))
        : expectedCertificates;
    return releaseMode && certs.isNotEmpty;
  }

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

class RepackagedDialog extends StatelessWidget {
  final IntegrityReport? report;
  final VoidCallback? onExit;

  const RepackagedDialog({
    super.key,
    this.report,
    this.onExit,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(
        Icons.warning_amber_rounded,
        color: Colors.redAccent,
        size: 48,
      ),
      title: const Text('App Tampering Detected'),
      content: Text(
        'This build of Kriya Code has been modified or repackaged by an untrusted source. '
        'The signing certificate does not match the official release certificate.\n\n'
        '${report?.reason ?? 'Untrusted build signature.'}',
      ),
      actions: [
        TextButton(
          onPressed: onExit ?? () => exit(0),
          child: const Text('Exit App'),
        ),
      ],
    );
  }
}

class RepackagedApp extends StatelessWidget {
  final IntegrityReport? report;
  final VoidCallback? onExit;

  const RepackagedApp({
    super.key,
    this.report,
    this.onExit,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFE53935),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: Scaffold(
        backgroundColor: const Color(0xFF1A1C1E),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: PopScope(
              canPop: false,
              child: RepackagedDialog(
                report: report,
                onExit: onExit,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> showRepackagedDialog(
  BuildContext context, {
  IntegrityReport? report,
  VoidCallback? onExit,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => PopScope(
      canPop: false,
      child: RepackagedDialog(
        report: report,
        onExit: onExit,
      ),
    ),
  );
}
