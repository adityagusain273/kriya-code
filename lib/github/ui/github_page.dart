import 'package:flutter/material.dart';

import '../../core/di.dart';
import '../api_client.dart';
import '../auth/token_store.dart';
import 'login_page.dart';
import 'repo_browser.dart';

class GitHubPage extends StatefulWidget {
  const GitHubPage({super.key});

  @override
  State<GitHubPage> createState() => _GitHubPageState();
}

class _GitHubPageState extends State<GitHubPage> {
  String? _token;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadToken();
  }

  Future<void> _loadToken() async {
    final token = await sl<TokenStore>().read();
    if (!mounted) return;
    setState(() {
      _token = token;
      _loading = false;
    });
  }

  /// Revokes the grant on GitHub before dropping the local copy.
  ///
  /// Clearing local storage alone leaves a live `repo`-scoped token on
  /// github.com, reachable by anyone who restored a backup or pulled the value
  /// off a compromised device. `docs/PRIVACY_POLICY.md` promises that signing
  /// out revokes access; this makes that true.
  Future<void> _signOut() async {
    final token = _token;
    if (token == null) return;

    var revocationFailed = false;
    if (token.isNotEmpty) {
      final result = await sl<GitHubApiClient>().revokeToken(token);
      revocationFailed = !result.isOk;
    }

    await sl<TokenStore>().clear();
    if (!mounted) return;
    setState(() => _token = null);

    if (!mounted) return;
    if (revocationFailed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Signed out on this device, but GitHub did not confirm revocation. '
            'Remove the token at github.com/settings/tokens.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return _token == null || _token!.isEmpty
        ? LoginPage(onAuthenticated: (token) => setState(() => _token = token))
        : RepoBrowser(
            token: _token!,
            onSignOut: _signOut,
          );
  }
}
