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
      final remoteRef =
          Reference.lookup(repo: repo, name: 'refs/remotes/origin/$branch');
      repo.reset(oid: remoteRef.target, resetType: GitReset.hard);
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
    try {
      final diff = Diff.treeToWorkdirWithIndex(repo: repo, tree: tree);
      final entries = <GitDiffEntry>[];
      final deltas = diff.deltas;
      final patches = diff.patches;
      for (var i = 0; i < deltas.length; i++) {
        final delta = deltas[i];
        entries.add(GitDiffEntry(
          path: delta.newFile.path,
          isNew: delta.status == GitDelta.added,
          isDeleted: delta.status == GitDelta.deleted,
          patch: i < patches.length ? patches[i].text : '',
        ));
      }
      for (final p in patches) {
        p.free();
      }
      diff.free();
      return Ok(entries);
    } catch (e) {
      return Err('Diff failed: $e');
    }
  }

  void disposeRepo(Repository repo) => repo.free();
}
