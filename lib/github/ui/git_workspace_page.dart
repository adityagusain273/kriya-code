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

  /// Set before the native handle is released.
  ///
  /// `dispose` called `Repository.free()` while an in-flight `workingDirDiff`
  /// could still be reading from it, which is a libgit2 use-after-free and
  /// crashes the process rather than raising a catchable Dart error.
  bool _disposed = false;

  GitService get _git => sl<GitService>();

  @override
  void initState() {
    super.initState();
    _openRepo();
  }

  Future<void> _openRepo() async {
    try {
      final repo = await _openImpl();
      if (_disposed) {
        repo.free();
        return;
      }
      _repo = repo;
      await _refreshDiff();
    } catch (e) {
      if (_disposed || !mounted) return;
      setState(() => _status = 'Failed to open repository: $e');
    }
  }

  Future<Repository> _openImpl() async {
    return Repository.open(widget.repoDir);
  }

  Future<void> _refreshDiff() async {
    final repo = _repo;
    if (repo == null || _disposed) return;
    final result = await _git.workingDirDiff(repo);
    if (_disposed || !mounted) return;
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

  /// Gates `pull`, which is `fetch` plus `reset --hard`.
  ///
  /// The hard reset rewinds HEAD to `origin/<branch>`, so anything only present
  /// locally is destroyed. Two distinct things can be lost and both must be
  /// called out: uncommitted working-tree changes, and commits that were never
  /// pushed. The previous check looked only at the working tree, so "commit
  /// locally, then pull" discarded the commits with no prompt at all.
  Future<void> _pullWithDirtyCheck() async {
    final repo = _repo;
    if (repo == null || _disposed) return;

    final unpushed =
        await _git.unpushedCommitCount(repo, widget.defaultBranch);
    final unpushedCount = unpushed.isOk ? unpushed.valueOrNull ?? 0 : 0;
    if (_disposed || !mounted) return;

    final warnings = <String>[];
    if (_changes.isNotEmpty) {
      warnings.add(
        '${_changes.length} uncommitted change(s) will be discarded.',
      );
    }
    if (unpushedCount > 0) {
      warnings.add(
        '$unpushedCount commit(s) that were never pushed will be lost. '
        'Push them first if you want to keep them.',
      );
    }

    if (warnings.isNotEmpty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Discard local work?'),
          content: Text(warnings.join('\n\n')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Discard and pull'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    if (_disposed || !mounted) return;
    await _action('Pull',
        () => _git.pull(repo, widget.token, branch: widget.defaultBranch));
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
    _disposed = true;
    final repo = _repo;
    _repo = null;
    repo?.free();
    super.dispose();
  }
}
