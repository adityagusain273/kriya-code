import 'package:flutter/material.dart';
import 'package:git2dart/git2dart.dart';

import '../../core/di.dart';
import '../../core/result.dart';
import '../git_service.dart';
import '../models.dart';
import 'diff_view.dart';

class GitWorkspacePage extends StatefulWidget {
  final String repoDir;
  final String token;
  final String defaultBranch;

  const GitWorkspacePage({
    super.key,
    required this.repoDir,
    required this.token,
    required this.defaultBranch,
  });

  @override
  State<GitWorkspacePage> createState() => _GitWorkspacePageState();
}

class _GitWorkspacePageState extends State<GitWorkspacePage> {
  bool _busy = false;
  String? _status;
  List<GitDiffEntry> _changes = [];
  Repository? _repo;

  GitService get _git => sl<GitService>();

  @override
  void initState() {
    super.initState();
    _openRepo();
  }

  Future<void> _openRepo() async {
    try {
      _repo = await _openImpl();
      await _refreshDiff();
    } catch (e) {
      setState(() => _status = 'Failed to open repository: $e');
    }
  }

  Future<Repository> _openImpl() async {
    return Repository.open(widget.repoDir);
  }

  Future<void> _refreshDiff() async {
    if (_repo == null) return;
    final result = await _git.workingDirDiff(_repo!);
    if (!mounted) return;
    setState(() {
      result.fold(
        (list) => _changes = list,
        (message) => _status = message,
      );
    });
  }

  Future<void> _action(String label, Future<Result<void>> Function() op) async {
    if (_busy || _repo == null) return;
    setState(() {
      _busy = true;
      _status = '$label…';
    });
    try {
      final result = await op();
      if (!mounted) return;
      setState(() => _status = result.fold((_) => '✔ $label complete', (m) => '✖ $m'));
      await _refreshDiff();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pullWithDirtyCheck() async {
    if (_changes.isNotEmpty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Uncommitted changes'),
          content: Text(
            'You have ${_changes.length} uncommitted change(s). '
            'Pulling will discard all local changes. Continue?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Pull anyway'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    await _action('Pull',
        () => _git.pull(_repo!, widget.token, branch: widget.defaultBranch));
  }

  Future<void> _commitDialog() async {
    final messageController = TextEditingController();
    final identity = sl<GitIdentityProvider>().identity;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Commit changes'),
        content: TextField(
          controller: messageController,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Commit message'),
          maxLines: 2,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
              onPressed: () =>
                  messageController.text.trim().isEmpty ? null : Navigator.pop(ctx, true),
              child: const Text('Commit')),
        ],
      ),
    );
    if (confirmed != true || _repo == null) return;
    await _action('Commit', () async {
      final r = await _git.commitAll(_repo!, messageController.text.trim(), identity);
      return r;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.repoDir.split('/').last),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _refreshDiff),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.download, size: 18),
                  label: const Text('Pull'),
                  onPressed: _busy
                      ? null
                      : () => _pullWithDirtyCheck(),
                ),
                FilledButton.icon(
                  icon: const Icon(Icons.commit, size: 18),
                  label: const Text('Commit'),
                  onPressed: _busy ? null : _commitDialog,
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.upload, size: 18),
                  label: const Text('Push'),
                  onPressed: _busy
                      ? null
                      : () => _action('Push',
                          () => _git.push(_repo!, widget.token, branch: widget.defaultBranch)),
                ),
              ],
            ),
          ),
          if (_status != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(_status!, style: Theme.of(context).textTheme.bodySmall),
            ),
          const Divider(),
          Expanded(
            child: _changes.isEmpty && !_busy
                ? const Center(child: Text('Working directory clean'))
                : ListView.builder(
                    itemCount: _changes.length,
                    itemBuilder: (context, i) {
                      final entry = _changes[i];
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          entry.isNew
                              ? Icons.add_circle_outline
                              : entry.isDeleted
                                  ? Icons.remove_circle_outline
                                  : Icons.edit_outlined,
                          size: 18,
                        ),
                        title: Text(entry.path, style: const TextStyle(fontSize: 13)),
                        subtitle: entry.patch.isEmpty ? null : const Text('view diff', style: TextStyle(fontSize: 11)),
                        onTap: entry.patch.isEmpty
                            ? null
                            : () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => DiffViewPage(
                                      path: entry.path,
                                      patch: entry.patch,
                                    ),
                                  ),
                                ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _repo?.free();
    super.dispose();
  }
}
