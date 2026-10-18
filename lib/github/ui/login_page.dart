import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/di.dart';
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
      if (mounted) setState(() => _status = 'Failed to start login: $e');
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _poll() async {
    final session = _session;
    if (session == null) return;
    try {
      final result = await _auth.pollOnce(session);
      switch (result.status) {
        case DeviceFlowStatus.success:
          _pollTimer?.cancel();
          await sl<TokenStore>().write(result.token!);
          if (mounted) widget.onAuthenticated(result.token!);
          break;
        case DeviceFlowStatus.pending:
          _schedulePoll();
          break;
        case DeviceFlowStatus.expired:
        case DeviceFlowStatus.denied:
        case DeviceFlowStatus.failed:
          _pollTimer?.cancel();
          if (mounted) setState(() => _status = 'Login ${result.status.name}. Try again.');
          break;
      }
    } catch (e) {
      _pollTimer?.cancel();
      if (mounted) setState(() => _status = 'Polling error: $e');
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
                  onPressed: () =>
                      launchUrl(Uri.parse(session.verificationUri), mode: LaunchMode.externalApplication),
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
