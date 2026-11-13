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
  String? _branch;
  int _stashCount = 0;

  /// Set before the native handle is released.
  ///
  /// `dispose` called `Repository.free()` while an in-flight `workingDirDiff`
  /// could still be reading from it, which is a libgit2 use-after-free and
  /// crashes the process rather than raising a catchable Dart error.
  bool _disposed = false;

  GitService get _git => sl<GitService>();

  String get _targetBranch => _branch ?? widget.defaultBranch;

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
      await _refreshMeta();
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

  Future<void> _refreshMeta() async {
    final repo = _repo;
    if (repo == null || _disposed) return;
    final branch = await _git.currentBranch(repo);
    final stashes = await _git.stashCount(repo);
    if (_disposed || !mounted) return;
    setState(() {
      _branch = branch.valueOrNull ?? _branch;
      _stashCount = stashes.valueOrNull ?? _stashCount;
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
      await _refreshMeta();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Gates `pull`, which is `fetch` plus a fast-forward reset.
  ///
  /// Pull refuses to rewind a branch that has commits the remote does not, so
  /// the only thing left to confirm is uncommitted working-tree changes, and
  /// those are only lost when the pull actually fast-forwards. A diverged pull
  /// is answered with the merge dialog rather than a bare refusal.
  Future<void> _pullWithDirtyCheck() async {
    final repo = _repo;
    if (repo == null || _disposed || _busy) return;

    if (_changes.isNotEmpty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Uncommitted changes'),
          content: Text(
            '${_changes.length} uncommitted change(s) will be discarded if this '
            'pull fast-forwards. A pull that needs a merge is refused instead.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Continue'),
            ),
          ],
        ),
      );
      if (confirmed != true || _disposed || !mounted) return;
    }

    final branch = _targetBranch;
    setState(() {
      _busy = true;
      _status = 'Pulling…';
    });
    Result<void> result;
    try {
      result = await _git.pull(repo, widget.token, branch: branch);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (_disposed || !mounted) return;

    if (result.isOk) {
      setState(() => _status = '✔ Pull complete');
      await _refreshDiff();
      return;
    }

    // The failed pull already fetched, so this comparison is fresh.
    final counts = (await _git.divergence(repo, branch)).valueOrNull;
    if (_disposed || !mounted) return;
    if (counts == null || !counts.hasDiverged) {
      setState(() => _status = '✖ ${result.errorOrNull}');
      return;
    }

    final merge = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Branches diverged'),
        content: Text(
          'origin/$branch has ${counts.behind} commit(s) you do not have, and you '
          'have ${counts.ahead} local commit(s) it does not. Nothing was changed. '
          'Merging combines both; push afterwards.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Merge'),
          ),
        ],
      ),
    );
    if (merge != true || _disposed || !mounted) return;
    await _action(
      'Merge origin/$branch',
      () => _git.mergeBranch(
        repo,
        'origin/$branch',
        sl<GitIdentityProvider>().identity,
      ),
    );
  }

  Future<void> _branchDialog() async {
    final repo = _repo;
    if (repo == null || _disposed || _busy) return;

    final local = await _git.localBranches(repo);
    if (_disposed || !mounted) return;
    if (!local.isOk) {
      setState(() => _status = '✖ ${local.errorOrNull}');
      return;
    }
    final remotes = (await _git.remoteBranches(repo)).valueOrNull ?? const [];

    if (_disposed || !mounted) return;
    final current = _targetBranch;
    final controller = TextEditingController();

    final chosen = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Branches · $current'),
        content: SizedBox(
          width: double.maxFinite,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 360),
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final name in local.valueOrNull ?? const <String>[])
                  ListTile(
                    dense: true,
                    title: Text(name),
                    trailing: name == current
                        ? const Text('current', style: TextStyle(fontSize: 11))
                        : const Icon(Icons.swap_horiz, size: 18),
                    onTap: name == current
                        ? null
                        : () => Navigator.pop(ctx, 'switch:$name'),
                  ),
                if (remotes.isNotEmpty) ...[
                  const Divider(),
                  const ListTile(
                    dense: true,
                    title: Text('Remote', style: TextStyle(fontSize: 12)),
                  ),
                  for (final name in remotes)
                    ListTile(
                      dense: true,
                      title: Text(name, style: const TextStyle(fontSize: 13)),
                      subtitle: const Text(
                        'tap to merge',
                        style: TextStyle(fontSize: 11),
                      ),
                      onTap: () => Navigator.pop(ctx, 'merge:$name'),
                    ),
                ],
                const Divider(),
                TextField(
                  controller: controller,
                  decoration: InputDecoration(
                    hintText: 'New branch from $current',
                    isDense: true,
                  ),
                  onSubmitted: (value) =>
                      Navigator.pop(ctx, 'create:${value.trim()}'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(ctx, 'create:${controller.text.trim()}'),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (chosen == null || _disposed || !mounted) return;
    final split = chosen.indexOf(':');
    final action = split < 0 ? chosen : chosen.substring(0, split);
    final value = split < 0 ? '' : chosen.substring(split + 1);
    if (value.isEmpty) return;

    switch (action) {
      case 'switch':
        await _action('Switch to $value', () => _git.switchBranch(repo, value));
      case 'create':
        await _action('Create $value', () => _git.createBranch(repo, value));
      case 'merge':
        await _action(
          'Merge $value',
          () => _git.mergeBranch(
            repo,
            value,
            sl<GitIdentityProvider>().identity,
          ),
        );
    }
  }

  Future<void> _stashDialog() async {
    final repo = _repo;
    if (repo == null || _disposed || _busy) return;

    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Stash · $_stashCount saved'),
        content: const Text(
          'Stash the tracked changes, or restore the most recent stash. '
          'Untracked files are not stashed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
          if (_stashCount > 0)
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'pop'),
              child: const Text('Restore'),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'save'),
            child: const Text('Stash changes'),
          ),
        ],
      ),
    );
    if (action == null || _disposed || !mounted) return;

    if (action == 'save') {
      await _action('Stash', () async {
        final saved = await _git.stashSave(
          repo,
          sl<GitIdentityProvider>().identity,
        );
        return saved.fold<Result<void>>(
          (stashed) =>
              stashed ? const Ok(null) : const Err('No tracked changes to stash.'),
          (message) => Err(message),
        );
      });
    } else {
      await _action('Restore stash', () => _git.stashPop(repo));
    }
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
                          () => _git.push(_repo!, widget.token, branch: _targetBranch)),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.account_tree, size: 18),
                  label: Text(_targetBranch),
                  onPressed: _busy ? null : _branchDialog,
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.inventory_2_outlined, size: 18),
                  label: Text('Stash · $_stashCount'),
                  onPressed: _busy ? null : _stashDialog,
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
