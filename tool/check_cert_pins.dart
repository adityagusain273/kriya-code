// Dials every host whose TLS trust anchor is pinned in
// lib/core/pinned_http.dart. A failure means the host moved to a different CA:
// refresh the PEM before releasing, otherwise sign-in, cloning and runtime
// downloads break for users with no way to recover except an app update.
//
// Usage: dart run tool/check_cert_pins.dart
import 'dart:io';

import 'package:kriya_code/core/pinned_http.dart';

Future<void> main() async {
  final client = PinnedHttpClient.create();
  var failed = false;

  for (final host in const [
    'api.github.com',
    'github.com',
    'packages.termux.dev',
  ]) {
    try {
      final response = await client.get(Uri.parse('https://$host/'));
      stdout.writeln('$host: TLS anchor OK (HTTP ${response.statusCode})');
    } catch (error) {
      failed = true;
      stderr.writeln('$host: FAILED — $error');
    }
  }

  client.close();
  if (failed) {
    stderr.writeln(
      'Refresh the PEM in lib/core/pinned_http.dart before releasing.',
    );
    exit(1);
  }
}
