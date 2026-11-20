import 'dart:io';

import 'package:git2dart/git2dart.dart';

import '../core/di.dart';
import '../core/result.dart';
import '../settings/settings_store.dart';
import 'models.dart';

class GitIdentity {
  final String name;
  final String email;

  const GitIdentity({required this.name, required this.email});
}

/// How far the local branch and its remote-tracking branch have moved apart.
class GitDivergence {
  final int ahead;
  final int behind;

  const GitDivergence({required this.ahead, required this.behind});

  bool get hasDiverged => ahead > 0 && behind > 0;
  bool get canFastForward => ahead == 0 && behind > 0;
}

class GitIdentityProvider {
  GitIdentity get identity {
    final store = sl<SettingsStore>();
    final name = store.gitName.trim();
    final email = store.gitEmail.trim();
    return GitIdentity(
      name: name.isNotEmpty ? name : 'Kriya User',
      email: email.isNotEmpty ? email : 'user@bcode.local',
    );
  }
}

class GitService {
  Callbacks _callbacks(String token) => Callbacks(
        credentials: UserPass(username: 'x-access-token', password: token),
      );

  /// Whether [url] is safe to hand to libgit2's clone.
  ///
  /// libgit2 honours the `ext::` transport, whose payload is executed by a
  /// shell, so only https is allowed at this boundary.
  static bool isAllowedCloneUrl(String url) {
    final uri = Uri.tryParse(url);
    return uri != null && uri.scheme == 'https';
  }

  Future<Result<Repository>> clone({
    required String httpsUrl,
    required String token,
    required String destinationPath,
  }) async {
    try {
      if (!isAllowedCloneUrl(httpsUrl)) {
        return Err('Only https:// clone URLs are supported.');
      }
      if (Directory(destinationPath).existsSync()) {
        return Ok(Repository.open(destinationPath));
      }
      final repo = Repository.clone(
        url: httpsUrl,
        localPath: destinationPath,
        callbacks: _callbacks(token),
      );
      return Ok(repo);
    } catch (e) {
      return Err('Clone failed: $e');
    }
  }

  // Credential material that must never ride along in a commit-all sweep,
  // however it ended up in the working tree.
  static final _secretPathPatterns = [
    RegExp(r'(^|/)\.env(\..*)?$'),
    RegExp(r'(^|/)\.git-credentials$'),
    RegExp(r'(^|/)\.npmrc$'),
    RegExp(r'(^|/)\.netrc$'),
    RegExp(r'(^|/)\.htpasswd$'),
    RegExp(r'(^|/)id_(rsa|dsa|ecdsa|ed25519)(\.pub)?$'),
    RegExp(r'(^|/)[^/]*\.(pem|key|p12|pfx|jks|keystore)$'),
    RegExp(r'(^|/)service-account[^/]*\.json$'),
  ];

  /// Whether [path] looks like credential material.
  static bool isSecretPath(String path) =>
      _secretPathPatterns.any((pattern) => pattern.hasMatch(path));

  Future<Result<void>> commitAll(
    Repository repo,
    String message,
    GitIdentity identity,
  ) async {
    try {
      final index = repo.index;
      // Staging must sweep '*' rather than repo.status: the default status
      // list omits untracked files entirely, so status-driven staging
      // silently skipped every newly created file. addAll still honours
      // .gitignore, so ignored material never enters the index.
      // Credential paths are then dropped, but only entries the add itself
      // introduced: removing an already-tracked secret would stage its
      // deletion in this commit, which would erase the file on the next
      // pull/checkout.
      final trackedBefore = index.map((e) => e.path).toSet();
      index.addAll(['*']);
      final staged = index.map((e) => e.path).toList();
      for (final path in staged) {
        if (isSecretPath(path) && !trackedBefore.contains(path)) {
          index.remove(path);
        }
      }
      index.write();
      final treeOid = index.writeTree();
      final tree = Tree.lookup(repo: repo, oid: treeOid);
      final signature = Signature.create(name: identity.name, email: identity.email);
      var parents = <Commit>[];
      try {
        final head = repo.head;
        parents = [Commit.lookup(repo: repo, oid: head.target)];
      } catch (_) {}
      Commit.create(
        repo: repo,
        updateRef: 'HEAD',
        author: signature,
        committer: signature,
        message: message,
        tree: tree,
        parents: parents,
      );
      return const Ok(null);
    } catch (e) {
      return Err('Commit failed: $e');
    }
  }

  Future<Result<void>> push(
    Repository repo,
    String token, {
    required String branch,
  }) async {
    try {
      final remote = Remote.lookup(repo: repo, name: 'origin');
      remote.push(
        refspecs: ['refs/heads/$branch'],
        callbacks: _callbacks(token),
      );
      return const Ok(null);
    } catch (e) {
      return Err('Push failed: $e');
    }
  }

  /// Ahead/behind counts between the local `branch` and `origin/<branch>`.
  ///
  /// A missing remote-tracking ref means nothing has been fetched yet, so every
  /// local commit is ahead and nothing is behind.
  Future<Result<GitDivergence>> divergence(
    Repository repo,
    String branch,
  ) async {
    try {
      final localOid = _tryRefTarget(repo, 'refs/heads/$branch');
      if (localOid == null) {
        return Err('Branch $branch does not exist.');
      }
      final remoteOid = _tryRefTarget(repo, 'refs/remotes/origin/$branch');
      if (remoteOid == null) {
        return Ok(GitDivergence(
          ahead: _countCommits(repo, localOid, null),
          behind: 0,
        ));
      }
      final counts = repo.aheadBehind(local: localOid, upstream: remoteOid);
      return Ok(GitDivergence(
        ahead: counts.isNotEmpty ? counts.first : 0,
        behind: counts.length > 1 ? counts[1] : 0,
      ));
    } catch (e) {
      return Err('Could not compare with origin/$branch: $e');
    }
  }

  /// Target of [refName], or null when the ref does not exist.
  ///
  /// `Reference.lookup` throws for a missing ref rather than returning null, so
  /// callers that treat "absent" as a normal outcome need this.
  static Oid? _tryRefTarget(Repository repo, String refName) {
    try {
      return Reference.lookup(repo: repo, name: refName).target;
    } catch (_) {
      return null;
    }
  }

  /// Counts commits reachable from [from] but not from [exclude].
  int _countCommits(Repository repo, Oid from, Oid? exclude) {
    final walk = RevWalk(repo);
    try {
      walk.push(from);
      if (exclude != null) walk.hide(exclude);
      final commits = walk.walk();
      var count = 0;
      for (final commit in commits) {
        commit.free();
        count++;
      }
      return count;
    } finally {
      walk.free();
    }
  }

  Future<Result<void>> pull(
    Repository repo,
    String token, {
    required String branch,
  }) async {
    try {
      final remote = Remote.lookup(repo: repo, name: 'origin');
      remote.fetch(
        refspecs: ['refs/heads/$branch'],
        callbacks: _callbacks(token),
      );
      final remoteOid = _tryRefTarget(repo, 'refs/remotes/origin/$branch');
      if (remoteOid == null) {
        // Must not fall through to a reset here: resetting to a missing target
        // discarded the local branch outright.
        return Err('The remote branch $branch does not exist. Nothing was changed.');
      }

      // Fast-forward only. `reset --hard` is safe when the local branch has
      // nothing of its own, and silently destroys work when it does: a user who
      // commits locally and then pulls used to lose those commits.
      final localOid = _tryRefTarget(repo, 'refs/heads/$branch');
      if (localOid != null) {
        final counts = repo.aheadBehind(local: localOid, upstream: remoteOid);
        final ahead = counts.isNotEmpty ? counts.first : 0;
        final behind = counts.length > 1 ? counts[1] : 0;
        if (ahead > 0 && behind > 0) {
          return Err(
            'Pull stopped: the branches diverged. origin/$branch has $behind '
            'commit(s) you do not have, and you have $ahead commit(s) it does '
            'not. Nothing was changed. Use Merge origin/$branch to combine both, '
            'then push.',
          );
        }
        if (ahead > 0) {
          return Err(
            'Pull stopped: $ahead local commit(s) are not on origin/$branch. '
            'Push them first. Nothing was changed.',
          );
        }
      }

      repo.reset(oid: remoteOid, resetType: GitReset.hard);
      return const Ok(null);
    } catch (e) {
      return Err('Pull failed: $e');
    }
  }

  /// Name of the branch HEAD points at, or an error on an unborn HEAD.
  Future<Result<String>> currentBranch(Repository repo) async {
    try {
      return Ok(repo.head.shorthand);
    } catch (e) {
      return Err('Could not read HEAD: $e');
    }
  }

  Future<Result<List<String>>> localBranches(Repository repo) async {
    try {
      final names = Branch.list(repo: repo, type: GitBranch.local)
          .map((branch) => branch.name)
          .toList()
        ..sort();
      return Ok(names);
    } catch (e) {
      return Err('Could not list local branches: $e');
    }
  }

  /// Remote-tracking branches, named as they appear to git ("origin/main").
  Future<Result<List<String>>> remoteBranches(Repository repo) async {
    try {
      final names = Branch.list(repo: repo, type: GitBranch.remote)
          .map((branch) => branch.name)
          .toList()
        ..sort();
      return Ok(names);
    } catch (e) {
      return Err('Could not list remote branches: $e');
    }
  }

  /// Creates [name] at the current HEAD without switching to it.
  Future<Result<void>> createBranch(Repository repo, String name) async {
    final branchName = name.trim();
    if (branchName.isEmpty) {
      return const Err('Branch name is empty.');
    }
    if (!Branch.isNameValid(branchName)) {
      return Err('"$branchName" is not a valid branch name.');
    }
    try {
      if (_tryRefTarget(repo, 'refs/heads/$branchName') != null) {
        return Err('Branch $branchName already exists.');
      }
      final head = repo.head;
      final target = Commit.lookup(repo: repo, oid: head.target);
      Branch.create(repo: repo, name: branchName, target: target).free();
      return const Ok(null);
    } catch (e) {
      return Err('Could not create $branchName: $e');
    }
  }

  /// Moves HEAD to an existing local branch.
  ///
  /// Refuses when tracked files are modified so a checkout cannot overwrite
  /// work in progress. Untracked files are left to libgit2's safe checkout,
  /// which only fails when the target branch would overwrite them.
  Future<Result<void>> switchBranch(Repository repo, String name) async {
    final branchName = name.trim();
    final refName = 'refs/heads/$branchName';
    if (_tryRefTarget(repo, refName) == null) {
      return Err('Branch $branchName does not exist.');
    }

    final dirty = await _trackedChanges(repo);
    final paths = dirty.valueOrNull;
    if (paths != null && paths.isNotEmpty) {
      return Err(
        '${paths.length} uncommitted change(s) in the working tree. '
        'Commit or stash them before switching to $branchName. Nothing was changed.',
      );
    }

    try {
      Checkout.reference(repo: repo, name: refName);
      repo.setHead(refName);
      return const Ok(null);
    } catch (e) {
      // A safe checkout can write some paths before it hits the one it must
      // not overwrite. HEAD did not move, so put the tree back to match it.
      try {
        Checkout.head(repo: repo);
      } catch (_) {}
      return Err(
        'Could not switch to $branchName: $e. '
        'Commit, stash or move any files the other branch would overwrite.',
      );
    }
  }

  /// Modified, staged or deleted tracked files, without untracked ones.
  Future<Result<List<String>>> _trackedChanges(Repository repo) async {
    final paths = await _workdirPaths(repo, includeUntracked: false);
    return paths.fold(
      (value) => Ok(value.tracked),
      (message) => Err(message),
    );
  }

  /// Files present in the working tree but tracked by neither HEAD nor index.
  Future<Result<List<String>>> _untrackedPaths(Repository repo) async {
    final paths = await _workdirPaths(repo, includeUntracked: true);
    return paths.fold(
      (value) => Ok(value.untracked),
      (message) => Err(message),
    );
  }

  /// Working-tree paths split by tracked/untracked.
  ///
  /// `treeToWorkdirWithIndex` is the only variant that reports staged additions
  /// (a file in the index but not in HEAD); untracked files only appear when
  /// they are asked for, because build output must not block a branch switch or
  /// a merge.
  Future<Result<({List<String> tracked, List<String> untracked})>>
      _workdirPaths(Repository repo, {required bool includeUntracked}) async {
    Tree? tree;
    try {
      final head = repo.head;
      tree = Commit.lookup(repo: repo, oid: head.target).tree;
    } catch (_) {
      // Unborn HEAD: nothing is tracked yet.
    }

    Diff? diff;
    try {
      diff = Diff.treeToWorkdirWithIndex(
        repo: repo,
        tree: tree,
        flags: includeUntracked
            ? const {GitDiff.includeUntracked, GitDiff.recurseUntrackedDirs}
            : const {GitDiff.normal},
      );
      final tracked = <String>[];
      final untracked = <String>[];
      for (final delta in diff.deltas) {
        (delta.status == GitDelta.untracked ? untracked : tracked)
            .add(_deltaPath(delta));
      }
      return Ok((tracked: tracked, untracked: untracked));
    } catch (e) {
      return Err('Could not read the working tree: $e');
    } finally {
      diff?.free();
    }
  }

  /// Saves the tracked working-tree changes and reverts them.
  ///
  /// Returns false when there was nothing to stash. Untracked files are left
  /// alone, matching `git stash` without `-u`.
  Future<Result<bool>> stashSave(
    Repository repo,
    GitIdentity identity, {
    String? message,
  }) async {
    final changes = await _trackedChanges(repo);
    final paths = changes.valueOrNull;
    if (paths != null && paths.isEmpty) {
      return const Ok(false);
    }
    try {
      final stasher = Signature.create(
        name: identity.name,
        email: identity.email,
      );
      Stash.create(repo: repo, stasher: stasher, message: message);
      return const Ok(true);
    } catch (e) {
      return Err('Stash failed: $e');
    }
  }

  Future<Result<int>> stashCount(Repository repo) async {
    try {
      return Ok(Stash.list(repo).length);
    } catch (e) {
      return Err('Could not read the stash: $e');
    }
  }

  /// Restores a stash without dropping it, for when `pop` would conflict.
  Future<Result<void>> stashApply(Repository repo, {int index = 0}) async {
    try {
      Stash.apply(repo: repo, index: index);
      return const Ok(null);
    } catch (e) {
      return Err(
        'Could not apply the stash: $e. The stash entry is still there; '
        'commit or stash your current changes first.',
      );
    }
  }

  /// Restores a stash and drops it on success.
  Future<Result<void>> stashPop(Repository repo, {int index = 0}) async {
    try {
      Stash.pop(repo: repo, index: index);
      return const Ok(null);
    } catch (e) {
      return Err(
        'Could not restore the stash: $e. The stash entry is still there and '
        'your current changes are intact.',
      );
    }
  }

  /// Merges [name] into the current branch.
  ///
  /// [name] may be a local branch ("feature"), a remote-tracking branch
  /// ("origin/main") or a full ref. The merge result is computed in memory
  /// first, so conflicting files are reported before the working tree is
  /// touched; a clean merge is written as a two-parent commit.
  Future<Result<void>> mergeBranch(
    Repository repo,
    String name,
    GitIdentity identity,
  ) async {
    final refName = _resolveRef(repo, name);
    if (refName == null) {
      return Err('No local or remote branch named $name.');
    }

    final dirty = await _trackedChanges(repo);
    final paths = dirty.valueOrNull;
    if (paths != null && paths.isNotEmpty) {
      return Err(
        '${paths.length} uncommitted change(s) in the working tree. '
        'Commit or stash them before merging. Nothing was changed.',
      );
    }

    try {
      final current = repo.head.shorthand;
      final localOid = _tryRefTarget(repo, 'refs/heads/$current');
      final theirOid = _tryRefTarget(repo, refName);
      if (localOid == null || theirOid == null) {
        return Err('Could not resolve $current or $name.');
      }
      if (localOid == theirOid) {
        return const Ok(null);
      }

      final counts = repo.aheadBehind(local: localOid, upstream: theirOid);
      final ahead = counts.isNotEmpty ? counts.first : 0;
      final behind = counts.length > 1 ? counts[1] : 0;
      if (behind == 0) {
        // Nothing on $name that the current branch does not already have.
        return const Ok(null);
      }
      if (ahead == 0) {
        repo.reset(oid: theirOid, resetType: GitReset.hard);
        return const Ok(null);
      }

      final ourCommit = Commit.lookup(repo: repo, oid: localOid);
      final theirCommit = Commit.lookup(repo: repo, oid: theirOid);
      final mergeIndex = Merge.commits(
        repo: repo,
        ourCommit: ourCommit,
        theirCommit: theirCommit,
      );
      try {
        if (mergeIndex.hasConflicts) {
          final files = mergeIndex.conflicts.keys.toList()..sort();
          return Err(
            'Merge stopped: ${files.length} file(s) conflict:\n${files.join('\n')}\n'
            'Your changes are intact; nothing was merged.',
          );
        }
        // libgit2's safe checkout overwrites untracked files silently, so a
        // merge that would replace one has to be refused before it starts.
        final untracked = await _untrackedPaths(repo);
        final blockers = (untracked.valueOrNull ?? const <String>[])
            .where(mergeIndex.find)
            .toList();
        if (blockers.isNotEmpty) {
          return Err(
            'Merge stopped: untracked file(s) would be overwritten:\n'
            '${blockers.join('\n')}\n'
            'Move or delete them first. Nothing was changed.',
          );
        }
        final treeOid = mergeIndex.writeTree(repo);
        final signature =
            Signature.create(name: identity.name, email: identity.email);
        final mergedOid = Commit.create(
          repo: repo,
          updateRef: 'HEAD',
          author: signature,
          committer: signature,
          message: 'Merge $name into $current',
          tree: Tree.lookup(repo: repo, oid: treeOid),
          parents: [ourCommit, theirCommit],
        );
        try {
          Checkout.commit(
            repo: repo,
            commit: Commit.lookup(repo: repo, oid: mergedOid),
          );
        } catch (e) {
          // The merge commit is already on the branch; an untracked file the
          // merge would overwrite can still stop the checkout. Put the branch
          // back before reporting, so HEAD and the tree agree again.
          repo.setHead('refs/heads/$current');
          repo.reset(oid: localOid, resetType: GitReset.hard);
          return Err('Merge failed: $e. The branch was put back to $current.');
        }
        return const Ok(null);
      } finally {
        mergeIndex.free();
      }
    } catch (e) {
      return Err('Merge failed: $e');
    }
  }

  String? _resolveRef(Repository repo, String name) {
    if (name.startsWith('refs/') && _tryRefTarget(repo, name) != null) {
      return name;
    }
    for (final candidate in ['refs/heads/$name', 'refs/remotes/$name']) {
      if (_tryRefTarget(repo, candidate) != null) return candidate;
    }
    return null;
  }

  static String _deltaPath(DiffDelta delta) =>
      delta.status == GitDelta.deleted || delta.newFile.path.isEmpty
          ? delta.oldFile.path
          : delta.newFile.path;

  Future<Result<List<GitDiffEntry>>> workingDirDiff(Repository repo) async {
    Tree? tree;
    try {
      final head = repo.head;
      tree = Commit.lookup(repo: repo, oid: head.target).tree;
    } catch (_) {}

    Diff? diff;
    List<Patch> patches = const [];
    try {
      diff = Diff.treeToWorkdirWithIndex(repo: repo, tree: tree);
      final entries = <GitDiffEntry>[];
      final deltas = diff.deltas;
      patches = diff.patches;
      for (var i = 0; i < deltas.length; i++) {
        final delta = deltas[i];
        entries.add(GitDiffEntry(
          path: _deltaPath(delta),
          isNew: delta.status == GitDelta.added,
          isDeleted: delta.status == GitDelta.deleted,
          patch: i < patches.length ? patches[i].text : '',
        ));
      }
      return Ok(entries);
    } catch (e) {
      return Err('Diff failed: $e');
    } finally {
      // Previously every free() was skipped when an exception was thrown
      // mid-loop, leaking a native object per failed refresh.
      for (final patch in patches) {
        patch.free();
      }
      diff?.free();
    }
  }

  void disposeRepo(Repository repo) => repo.free();
}
