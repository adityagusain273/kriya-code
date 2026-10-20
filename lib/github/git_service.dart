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

class GitIdentityProvider {
  GitIdentity get identity {
    final store = sl<SettingsStore>();
    final name = store.gitName.trim();
    final email = store.gitEmail.trim();
    return GitIdentity(
      name: name.isNotEmpty ? name : 'B Code User',
      email: email.isNotEmpty ? email : 'user@bcode.local',
    );
  }
}

class GitService {
  Callbacks _callbacks(String token) => Callbacks(
        credentials: UserPass(username: 'x-access-token', password: token),
      );

  Future<Result<Repository>> clone({
    required String httpsUrl,
    required String token,
    required String destinationPath,
  }) async {
    try {
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

  Future<Result<void>> commitAll(
    Repository repo,
    String message,
    GitIdentity identity,
  ) async {
    try {
      final index = repo.index;
      index.addAll(['*']);
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

  /// Commits on `branch` that the remote does not have.
  ///
  /// Callers must check this before a hard reset. `reset --hard` rewinds HEAD to
  /// `origin/<branch>`, which discards every local commit made since the fork
  /// point. The confirmation dialog used to gate on the working tree only, so
  /// "commit locally, then pull" lost the commits with no prompt at all.
  Future<Result<int>> unpushedCommitCount(
    Repository repo,
    String branch,
  ) async {
    // Reference.lookup throws when the ref does not exist rather than returning
    // null, so a missing tracking ref has to be probed for.
    try {
      final localRef = Reference.lookup(repo: repo, name: 'refs/heads/$branch');
      final localOid = localRef.target;

      final remoteOid = _tryRefTarget(repo, 'refs/remotes/origin/$branch');

      if (remoteOid == null) {
        // No tracking ref yet, so everything reachable from the branch is local.
        return Ok(_countCommits(repo, localOid, null));
      }

      final counts = repo.aheadBehind(local: localOid, upstream: remoteOid);
      return Ok(counts.isNotEmpty ? counts.first : 0);
    } catch (e) {
      return Err('Could not compare with the remote: $e');
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

      repo.reset(oid: remoteOid, resetType: GitReset.hard);
      return const Ok(null);
    } catch (e) {
      return Err('Pull failed: $e');
    }
  }

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
          // For a deletion the "new" side is the absent one, and reading its
          // path is either empty or a null dereference. Use the old side.
          path: delta.status == GitDelta.deleted
              ? delta.oldFile.path
              : delta.newFile.path,
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
