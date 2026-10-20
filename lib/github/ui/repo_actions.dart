import 'package:flutter/material.dart';

import '../../core/di.dart';
import '../../workspace/fs_service.dart';
import '../api_client.dart';
import '../git_service.dart';
import '../models.dart';
import 'commit_list.dart';
import 'git_workspace_page.dart';

class RepoActionsPage extends StatefulWidget {
  final GHRepo repo;
  final String token;

  const RepoActionsPage({super.key, required this.repo, required this.token});

  @override
  State<RepoActionsPage> createState() => _RepoActionsPageState();
}

class _RepoActionsPageState extends State<RepoActionsPage> {
  bool _busy = false;
  String? _message;

  static final RegExp _repoNameChars = RegExp(r'[^A-Za-z0-9._\-/]');

  /// The API-provided name is joined into filesystem paths; keep it on the safe
  /// form `owner/repo` so nothing can turn a repo name into a traversal.
  String get _safeFullName =>
      widget.repo.fullName.replaceAll(_repoNameChars, '_');

  String get _cloneDir {
    final root = sl<FsService>().rootPath;
    return '$root/repos/$_safeFullName';
  }

  bool get _alreadyCloned {
    try {
      return sl<FsService>().exists('repos/$_safeFullName/.git');
    } catch (_) {
      return false;
    }
  }

  Future<void> _clone() async {
    setState(() {
      _busy = true;
      _message = 'Cloning ${widget.repo.fullName}…';
    });
    try {
      await sl<FsService>().createDirectory('repos');
      final result = await sl<GitService>().clone(
        httpsUrl: 'https://github.com/${widget.repo.fullName}.git',
        token: widget.token,
        destinationPath: _cloneDir,
      );
      if (!mounted) return;
      setState(() => _message = result.fold((_) => 'Cloned successfully', (e) => e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = widget.repo;
    return Scaffold(
      appBar: AppBar(title: Text(repo.fullName)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (repo.description.isNotEmpty) ...[
              Text(repo.description),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                Chip(label: Text('default: ${repo.defaultBranch}', style: const TextStyle(fontSize: 11))),
                if (repo.isPrivate)
                  const Padding(
                    padding: EdgeInsets.only(left: 6),
                    child: Icon(Icons.lock_outline, size: 16),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: Icon(_alreadyCloned ? Icons.folder_open : Icons.download),
              label: Text(_alreadyCloned ? 'Open Cloned Copy' : 'Clone to Workspace'),
              onPressed: _busy ? null : (_alreadyCloned ? _openWorkspace : _clone),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.history),
              label: const Text('View Commit History'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CommitListPage(
                    repo: repo.fullName,
                    token: widget.token,
                    client: sl<GitHubApiClient>(),
                  ),
                ),
              ),
            ),
            if (_busy) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
            if (_message != null) ...[
              const SizedBox(height: 12),
              Text(_message!, style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }

  void _openWorkspace() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GitWorkspacePage(
          repoDir: _cloneDir,
          token: widget.token,
          defaultBranch: widget.repo.defaultBranch,
        ),
      ),
    );
  }
}
