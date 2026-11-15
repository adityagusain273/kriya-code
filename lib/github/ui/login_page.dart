import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/di.dart';
import '../../workspace/mdi.dart';
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

  void _cancelSession() {
    _pollTimer?.cancel();
    setState(() {
      _session = null;
      _starting = false;
      _status = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Sign in with GitHub')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: cs.primary.withValues(alpha: 0.28),
                        width: 1.5,
                      ),
                    ),
                    child: Icon(Mdi.github, size: 30, color: cs.primary),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Connect GitHub',
                  textAlign: TextAlign.center,
                  style: text.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Clone repositories, inspect diffs, and push commits directly from your mobile workspace.',
                  textAlign: TextAlign.center,
                  style: text.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 24),
                if (session == null) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: cs.outlineVariant.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.info_outline_rounded,
                                size: 18, color: cs.primary),
                            const SizedBox(width: 8),
                            Text(
                              'How it works',
                              style: text.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        const _StepRow(
                          number: '1',
                          title: 'Request a one-time code',
                          subtitle:
                              'Tap continue to generate a temporary 8-character device code.',
                        ),
                        const SizedBox(height: 12),
                        const _StepRow(
                          number: '2',
                          title: 'Authorize on github.com',
                          subtitle:
                              'Paste the code in your browser and approve B Code.',
                        ),
                        const SizedBox(height: 12),
                        const _StepRow(
                          number: '3',
                          title: 'Start coding',
                          subtitle:
                              'Return to B Code. Your repositories load automatically.',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: cs.outlineVariant.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.shield_outlined,
                                size: 18, color: cs.primary),
                            const SizedBox(width: 8),
                            Text(
                              'Security & Privacy',
                              style: text.labelLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        const _SecurityItem(
                          icon: Icons.key_off_outlined,
                          text:
                              'No passwords entered here. You authorize on GitHub directly.',
                        ),
                        const SizedBox(height: 8),
                        const _SecurityItem(
                          icon: Icons.lock_outline_rounded,
                          text:
                              'Access tokens are stored encrypted on-device only.',
                        ),
                        const SizedBox(height: 8),
                        const _SecurityItem(
                          icon: Icons.logout_rounded,
                          text:
                              'Revocable anytime from GitHub settings or by signing out.',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 48,
                    child: FilledButton.icon(
                      onPressed: _starting ? null : _startLogin,
                      icon: _starting
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: cs.onPrimary,
                              ),
                            )
                          : const Icon(Icons.arrow_forward_rounded, size: 18),
                      label: Text(
                        _starting ? 'Requesting code…' : 'Continue with GitHub',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: cs.primary.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: cs.primary,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            'Waiting for authorization on GitHub…',
                            style: TextStyle(
                              color: cs.primary,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: cs.outlineVariant.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(
                          'YOUR ONE-TIME DEVICE CODE',
                          style: text.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            letterSpacing: 1.2,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 12),
                        SelectableText(
                          session.userCode,
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 4,
                            fontFamily: 'monospace',
                            color: cs.onSurface,
                          ),
                        ),
                        const SizedBox(height: 10),
                        InkWell(
                          onTap: () async {
                            await Clipboard.setData(
                              ClipboardData(text: session.userCode),
                            );
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Code copied to clipboard'),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            }
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.check_circle_rounded,
                                    size: 15, color: cs.primary),
                                const SizedBox(width: 6),
                                Text(
                                  'Copied to clipboard',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: cs.primary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 48,
                    child: FilledButton.icon(
                      icon: const Icon(Icons.open_in_new_rounded, size: 18),
                      label: const Text(
                        'Open github.com/login/device',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () => _openVerificationPage(session),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Paste the code in your browser, tap Authorize, then return here.',
                    textAlign: TextAlign.center,
                    style: text.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _cancelSession,
                    child: const Text('Cancel and start over'),
                  ),
                ],
                if (_status.isNotEmpty && session == null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _status,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: cs.error, fontSize: 13),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  final String number;
  final String title;
  final String subtitle;

  const _StepRow({
    required this.number,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          margin: const EdgeInsets.only(top: 1),
          decoration: BoxDecoration(
            color: cs.primary.withValues(alpha: 0.15),
            shape: BoxShape.circle,
            border: Border.all(
              color: cs.primary.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            number,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: cs.primary,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: text.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: text.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SecurityItem extends StatelessWidget {
  final IconData icon;
  final String text;

  const _SecurityItem({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final label = Theme.of(context).textTheme.bodySmall;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: cs.primary.withValues(alpha: 0.85)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: label?.copyWith(
              color: cs.onSurfaceVariant,
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}
