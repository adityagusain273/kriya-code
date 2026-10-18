import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/di.dart';
import '../api_client.dart';
import 'repo_browser_model.dart';
import 'repo_actions.dart';

class RepoBrowser extends StatelessWidget {
  final String token;
  final Future<void> Function() onSignOut;

  const RepoBrowser({super.key, required this.token, required this.onSignOut});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => RepoBrowserModel(sl<GitHubApiClient>(), token)..loadRepos(),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Your Repositories'),
          actions: [
            IconButton(icon: const Icon(Icons.logout), tooltip: 'Sign out', onPressed: onSignOut),
          ],
        ),
        body: Consumer<RepoBrowserModel>(
          builder: (context, model, _) {
            if (model.loading) return const Center(child: CircularProgressIndicator());
            if (model.error != null) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(model.error!, textAlign: TextAlign.center),
                    TextButton(onPressed: model.loadRepos, child: const Text('Retry')),
                  ],
                ),
              );
            }
            return ListView.builder(
              itemCount: model.repos.length,
              itemBuilder: (context, i) {
                final repo = model.repos[i];
                return ListTile(
                  leading: Icon(
                    repo.isPrivate ? Icons.lock_outline : Icons.public,
                    color: Colors.grey,
                  ),
                  title: Text(repo.fullName),
                  subtitle: Text(
                    repo.description.isEmpty ? '(no description)' : repo.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Text(_fmtDate(repo.updatedAt), style: const TextStyle(fontSize: 11)),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => RepoActionsPage(repo: repo, token: token),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
