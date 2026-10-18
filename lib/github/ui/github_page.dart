import 'package:flutter/material.dart';

import '../../core/di.dart';
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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return _token == null || _token!.isEmpty
        ? LoginPage(onAuthenticated: (token) => setState(() => _token = token))
        : RepoBrowser(
            token: _token!,
            onSignOut: () async {
              await sl<TokenStore>().clear();
              setState(() => _token = null);
            },
          );
  }
}
