import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/di.dart';
import '../api_client.dart';
import '../auth/device_flow_auth.dart';
import '../auth/token_store.dart';

class LoginPage extends StatefulWidget {
  final ValueChanged<String> onAuthenticated;

  const LoginPage({super.key, required this.onAuthenticated});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  DeviceFlowSession? _session;
  bool _starting = false;
  String _status = '';
  Timer? _pollTimer;

  DeviceFlowAuth get _auth => sl<DeviceFlowAuth>();

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  void _schedulePoll() {
    final session = _session;
    if (session == null || !mounted) return;
    _pollTimer?.cancel();
    _pollTimer = Timer(Duration(seconds: session.intervalSeconds), _poll);
  }

  Future<void> _startLogin() async {
    setState(() {
      _starting = true;
      _status = 'Requesting device code from GitHub…';
    });
    try {
      final session = await _auth.start();
      if (!mounted) return;
      setState(() {
        _session = session;
        _status = 'Waiting for authorization…';
      });
      await Clipboard.setData(ClipboardData(text: session.userCode));
      _schedulePoll();
    } catch (e) {
      // `$e` on a StateError prefixes the useful sentence with "Bad state: ", and
      // a bare status code told the user nothing they could act on.
      if (mounted) setState(() => _status = _readable(e));
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _poll() async {
    final session = _session;
    if (session == null) return;
    try {
      final result = await _auth.pollOnce(session);
      if (!mounted) return;
      switch (result.status) {
        case DeviceFlowStatus.success:
          _pollTimer?.cancel();
          setState(() => _status = 'Verifying…');

          // Confirm the token actually works before it is persisted. A 200 with
          // an access_token is the only thing the exchange guarantees, and the
          // token carries `repo` scope, so storing an unverified one means the
          // app treats the user as signed in against an unusable credential.
          final verified = await sl<GitHubApiClient>().getUser(result.token!);
          if (!mounted) return;
          if (!verified.isOk) {
            setState(() =>
                _status = 'GitHub rejected that sign-in: ${verified.errorOrNull}');
            return;
          }
          final user = verified.valueOrNull;
          await sl<TokenStore>().write(result.token!);
          if (!mounted) return;
          setState(() => _status = 'Signed in as ${user?.login ?? 'GitHub user'}.');
          widget.onAuthenticated(result.token!);
          break;
        case DeviceFlowStatus.pending:
          _schedulePoll();
          break;
        case DeviceFlowStatus.expired:
        case DeviceFlowStatus.denied:
        case DeviceFlowStatus.failed:
          _pollTimer?.cancel();
          setState(() {
            _status = result.message?.isNotEmpty == true
                ? result.message!
                : 'Login ${result.status.name}. Try again.';
          });
          break;
      }
    } catch (e) {
      _pollTimer?.cancel();
      if (mounted) setState(() => _status = _readable(e));
    }
  }

  /// Strips the `Bad state: ` noise Dart adds when a StateError's message is used
  /// as the display string.
  static String _readable(Object error) {
    final text = error.toString();
    return text.startsWith('Bad state: ') ? text.substring(11) : text;
  }

  /// `verification_uri` is a server-supplied string that used to be handed
  /// straight to the system launcher. Only https://github.com is allowed, so a
  /// hostile or compromised response cannot hand the user an `intent://` or
  /// `file://` URI to approve.
  Future<void> _openVerificationPage(DeviceFlowSession session) async {
    if (!DeviceFlowAuth.isSafeVerificationUri(session.verificationUri)) {
      setState(() => _status =
          'GitHub returned an unexpected sign-in URL. Open github.com/login/device manually.');
      return;
    }
    final launched = await launchUrl(
      Uri.parse(session.verificationUri),
      mode: LaunchMode.externalApplication,
    );
    if (!launched && mounted) {
      setState(() => _status = 'Could not open a browser. '
          'Visit github.com/login/device and enter the code above.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    return Scaffold(
      appBar: AppBar(title: const Text('Sign in with GitHub')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.account_circle_outlined, size: 72),
              const SizedBox(height: 16),
              Text(
                'B Code connects to your GitHub account using the secure Device Flow. '
                'No password ever enters the app.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 32),
              if (session == null)
                FilledButton.icon(
                  onPressed: _starting ? null : _startLogin,
                  icon: const Icon(Icons.login),
                  label: Text(_starting ? 'Connecting…' : 'Continue with GitHub'),
                )
              else ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Text('Enter this code on GitHub',
                            style: Theme.of(context).textTheme.bodySmall),
                        const SizedBox(height: 8),
                        SelectableText(
                          session.userCode,
                          style: const TextStyle(
                              fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 2),
                        ),
                        const SizedBox(height: 4),
                        const Text('(copied to clipboard)', style: TextStyle(fontSize: 11)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Open github.com/login/device'),
                  onPressed: () => _openVerificationPage(session),
                ),
              ],
              const SizedBox(height: 16),
              if (_status.isNotEmpty)
                Text(_status,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Theme.of(context).colorScheme.primary)),
            ],
          ),
        ),
      ),
    );
  }
}
