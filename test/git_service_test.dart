import 'dart:io';

import 'package:kriya_code/github/git_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:git2dart/git2dart.dart';

void main() {
  group('clone URL guard', () {
    test('accepts https URLs', () {
      expect(
        GitService.isAllowedCloneUrl('https://github.com/user/repo.git'),
        isTrue,
      );
      expect(
        GitService.isAllowedCloneUrl('https://github.com/user/repo'),
        isTrue,
      );
    });

    test('rejects every non-https scheme', () {
      const urls = [
        'ext::sh -c touch /tmp/pwned',
        'file:///etc/passwd',
        'ssh://git@github.com/user/repo.git',
        'git://github.com/user/repo.git',
        'http://github.com/user/repo.git',
        'ftp://example.com/repo.git',
        'git@github.com:user/repo.git',
        '',
      ];
      for (final url in urls) {
        expect(GitService.isAllowedCloneUrl(url), isFalse, reason: url);
      }
    });

    test('clone reports an Err without touching libgit2 for a bad scheme',
        () async {
      final service = GitService();
      final result = await service.clone(
        httpsUrl: 'ext::sh -c touch /tmp/bcode-clone-guard-pwned',
        token: 'token',
        destinationPath:
            '${Directory.systemTemp.path}/bcode-clone-guard-dest',
      );

      expect(result.isOk, isFalse);
      expect(result.errorOrNull, contains('https'));
      expect(File('/tmp/bcode-clone-guard-pwned').existsSync(), isFalse);
    });
  });

  group('commitAll secret exclusions', () {
    test('recognises credential files anywhere in the tree', () {
      const secrets = [
        '.env',
        '.env.production',
        'config/.env',
        '.git-credentials',
        'sub/.git-credentials',
        '.npmrc',
        '.netrc',
        '.htpasswd',
        'keys/id_rsa',
        'id_ed25519',
        'id_rsa.pub',
        'server.pem',
        'tls/host.key',
        'cert.p12',
        'cert.pfx',
        'app.jks',
        'release.keystore',
        'service-account-prod.json',
      ];
      for (final path in secrets) {
        expect(GitService.isSecretPath(path), isTrue, reason: path);
      }
    });

    test('leaves ordinary project files alone', () {
      const ordinary = [
        'main.dart',
        'lib/main.dart',
        'pubspec.yaml',
        'README.md',
        'keynote.txt',
        'assets/environment.json',
        'src/env.dart',
      ];
      for (final path in ordinary) {
        expect(GitService.isSecretPath(path), isFalse, reason: path);
      }
    });
  });

  group('commitAll staging sweep', () {
    late Directory tmp;
    late Repository repo;
    const identity = GitIdentity(name: 'Test User', email: 'test@bcode.local');
    final service = GitService();

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('bcode_commitall_');
      repo = Repository.init(path: '${tmp.path}/repo');
    });

    tearDown(() {
      repo.free();
      tmp.deleteSync(recursive: true);
    });

    Tree headTree(Repository repo) =>
        Commit.lookup(repo: repo, oid: repo.head.target).tree;

    List<String> entryNames(Tree tree) =>
        tree.entries.map((e) => e.name).toList();

    test('commits a newly created untracked file and skips .env', () async {
      File('${repo.workdir}/tracked.txt').writeAsStringSync('one');
      final first = await service.commitAll(repo, 'initial', identity);
      expect(first.isOk, isTrue);
      expect(entryNames(headTree(repo)), contains('tracked.txt'));

      // repo.status (default options) omits untracked files, so the sweep
      // must stage via addAll('*'): fresh.txt would otherwise never be
      // committed.
      File('${repo.workdir}/fresh.txt').writeAsStringSync('new file');
      File('${repo.workdir}/.env').writeAsStringSync('SECRET_TOKEN=x');

      final second = await service.commitAll(repo, 'add fresh', identity);
      expect(second.isOk, isTrue);

      final names = entryNames(headTree(repo));
      expect(names, contains('fresh.txt'));
      expect(names, contains('tracked.txt'));
      expect(names, isNot(contains('.env')));
      // Dropping the secret from the index must not touch the working tree.
      expect(File('${repo.workdir}/.env').existsSync(), isTrue);
    });

    test('ignores gitignored working files', () async {
      File('${repo.workdir}/.gitignore').writeAsStringSync('payload.log\n');
      File('${repo.workdir}/tracked.txt').writeAsStringSync('one');
      File('${repo.workdir}/payload.log').writeAsStringSync('noise');

      final result = await service.commitAll(repo, 'initial', identity);
      expect(result.isOk, isTrue);

      expect(entryNames(headTree(repo)), containsAll(['tracked.txt', '.gitignore']));
      expect(entryNames(headTree(repo)), isNot(contains('payload.log')));
    });

    test('does not stage a deletion of an already-tracked secret', () async {
      // A user may have committed .env deliberately long ago; the sweep must
      // leave it tracked rather than staging its deletion (data loss on pull).
      File('${repo.workdir}/tracked.txt').writeAsStringSync('one');
      File('${repo.workdir}/.env').writeAsStringSync('SECRET_TOKEN=x');
      final index = repo.index;
      index.addAll(['*']);
      index.write();
      final signature =
          Signature.create(name: identity.name, email: identity.email);
      Commit.create(
        repo: repo,
        updateRef: 'HEAD',
        author: signature,
        committer: signature,
        message: 'initial',
        tree: Tree.lookup(repo: repo, oid: index.writeTree()),
        parents: const [],
      );
      final headOid = repo.head.target;

      File('${repo.workdir}/tracked.txt').writeAsStringSync('two');
      final result = await service.commitAll(repo, 'update', identity);
      expect(result.isOk, isTrue);

      final names = entryNames(headTree(repo));
      expect(names, contains('.env'));
      expect(names, contains('tracked.txt'));
      // The commit must differ from its parent (real change), and .env must
      // survive unchanged: same tree entry content, no forced removal.
      final newTree = headTree(repo);
      expect(newTree.oid, isNot(equals(headOid)));
      expect(
        Blob.lookup(repo: repo, oid: newTree['.env'].oid).content,
        equals('SECRET_TOKEN=x'),
      );
      expect(
        Blob.lookup(repo: repo, oid: newTree['tracked.txt'].oid).content,
        equals('two'),
      );
    });
  });

  group('branch management', () {
    late Directory tmp;
    late Repository repo;
    final service = GitService();
    const identity = GitIdentity(name: 'Test User', email: 'test@bcode.local');

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('bcode_branch_');
      repo = Repository.init(path: '${tmp.path}/repo');
    });

    tearDown(() {
      repo.free();
      tmp.deleteSync(recursive: true);
    });

    String pathOf(String name) => '${repo.workdir}/$name';

    Future<String> baseBranch() async {
      final current = await service.currentBranch(repo);
      expect(current.isOk, isTrue, reason: current.errorOrNull);
      return current.valueOrNull!;
    }

    Future<void> commit(String name, String content, String message) async {
      File(pathOf(name)).writeAsStringSync(content);
      final result = await service.commitAll(repo, message, identity);
      expect(result.isOk, isTrue, reason: result.errorOrNull);
    }

    test('lists local branches and reports the current one', () async {
      await commit('shared.txt', 'one', 'initial');
      final base = await baseBranch();

      final created = await service.createBranch(repo, 'feature');
      expect(created.isOk, isTrue, reason: created.errorOrNull);

      final local = await service.localBranches(repo);
      expect(local.isOk, isTrue, reason: local.errorOrNull);
      expect(local.valueOrNull, containsAll([base, 'feature']));

      final remote = await service.remoteBranches(repo);
      expect(remote.valueOrNull, isEmpty);
      expect(await baseBranch(), base);
    });

    test('creates a branch from HEAD and switches to it', () async {
      await commit('shared.txt', 'one', 'initial');
      final base = await baseBranch();

      expect((await service.createBranch(repo, 'feature')).isOk, isTrue);
      expect((await service.switchBranch(repo, 'feature')).isOk, isTrue);
      expect(await baseBranch(), 'feature');
      expect(File(pathOf('shared.txt')).readAsStringSync(), 'one');

      await commit('feature.txt', 'feature work', 'feature commit');
      expect((await service.switchBranch(repo, base)).isOk, isTrue);
      expect(await baseBranch(), base);
      expect(File(pathOf('feature.txt')).existsSync(), isFalse);
      expect(File(pathOf('shared.txt')).readAsStringSync(), 'one');
    });

    test('refuses to switch with a dirty tree and leaves the edits alone',
        () async {
      await commit('shared.txt', 'one', 'initial');
      final base = await baseBranch();
      await service.createBranch(repo, 'feature');
      await service.switchBranch(repo, 'feature');

      File(pathOf('shared.txt')).writeAsStringSync('modified on feature');
      final result = await service.switchBranch(repo, base);

      expect(result.isOk, isFalse);
      expect(result.errorOrNull, contains('uncommitted'));
      expect(await baseBranch(), 'feature');
      expect(
        File(pathOf('shared.txt')).readAsStringSync(),
        'modified on feature',
      );
    });

    test('rejects a duplicate, an invalid and an empty branch name', () async {
      await commit('shared.txt', 'one', 'initial');
      expect((await service.createBranch(repo, 'feature')).isOk, isTrue);

      final duplicate = await service.createBranch(repo, 'feature');
      expect(duplicate.isOk, isFalse);
      expect(duplicate.errorOrNull, contains('already exists'));

      final invalid = await service.createBranch(repo, 'bad~name');
      expect(invalid.isOk, isFalse);
      expect(invalid.errorOrNull, contains('valid branch name'));

      final empty = await service.createBranch(repo, '  ');
      expect(empty.isOk, isFalse);
      expect(empty.errorOrNull, contains('empty'));
    });

    test('switching to a missing branch is an Err', () async {
      await commit('shared.txt', 'one', 'initial');
      final result = await service.switchBranch(repo, 'nope');
      expect(result.isOk, isFalse);
      expect(result.errorOrNull, contains('does not exist'));
    });

    test('a staged addition blocks a switch', () async {
      await commit('shared.txt', 'one', 'initial');
      final base = await baseBranch();
      await service.createBranch(repo, 'feature');
      await service.switchBranch(repo, 'feature');

      File(pathOf('staged.txt')).writeAsStringSync('staged');
      final index = repo.index;
      index.addAll(['staged.txt']);
      index.write();

      final result = await service.switchBranch(repo, base);
      expect(result.isOk, isFalse);
      expect(result.errorOrNull, contains('uncommitted'));
      expect(await baseBranch(), 'feature');
    });

    test('an untracked file does not block a switch', () async {
      await commit('shared.txt', 'one', 'initial');
      final base = await baseBranch();
      await service.createBranch(repo, 'feature');
      await service.switchBranch(repo, 'feature');

      File(pathOf('build.log')).writeAsStringSync('noise');
      final result = await service.switchBranch(repo, base);

      expect(result.isOk, isTrue, reason: result.errorOrNull);
      expect(await baseBranch(), base);
      expect(File(pathOf('build.log')).readAsStringSync(), 'noise');
    });
  });

  group('stash', () {
    late Directory tmp;
    late Repository repo;
    final service = GitService();
    const identity = GitIdentity(name: 'Test User', email: 'test@bcode.local');

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('bcode_stash_');
      repo = Repository.init(path: '${tmp.path}/repo');
    });

    tearDown(() {
      repo.free();
      tmp.deleteSync(recursive: true);
    });

    String pathOf(String name) => '${repo.workdir}/$name';

    Future<void> commit(String name, String content) async {
      File(pathOf(name)).writeAsStringSync(content);
      final result = await service.commitAll(repo, 'initial', identity);
      expect(result.isOk, isTrue, reason: result.errorOrNull);
    }

    test('saves the working tree and restores it byte for byte', () async {
      await commit('notes.txt', 'original\n');

      File(pathOf('notes.txt')).writeAsStringSync('edited\n');
      final saved = await service.stashSave(repo, identity, message: 'wip');
      expect(saved.valueOrNull, isTrue);
      expect(File(pathOf('notes.txt')).readAsStringSync(), 'original\n');
      expect((await service.stashCount(repo)).valueOrNull, 1);

      final popped = await service.stashPop(repo);
      expect(popped.isOk, isTrue, reason: popped.errorOrNull);
      expect(File(pathOf('notes.txt')).readAsStringSync(), 'edited\n');
      expect((await service.stashCount(repo)).valueOrNull, 0);
    });

    test('reports nothing to stash on a clean tree', () async {
      await commit('notes.txt', 'original\n');
      final result = await service.stashSave(repo, identity);
      expect(result.valueOrNull, isFalse);
      expect((await service.stashCount(repo)).valueOrNull, 0);
    });

    test('pop keeps the stash when local edits would be overwritten', () async {
      await commit('notes.txt', 'original\n');
      File(pathOf('notes.txt')).writeAsStringSync('first edit\n');
      expect((await service.stashSave(repo, identity)).valueOrNull, isTrue);

      File(pathOf('notes.txt')).writeAsStringSync('second edit\n');
      final popped = await service.stashPop(repo);

      expect(popped.isOk, isFalse);
      expect(File(pathOf('notes.txt')).readAsStringSync(), 'second edit\n');
      expect((await service.stashCount(repo)).valueOrNull, 1);

      final applied = await service.stashApply(repo);
      expect(applied.isOk, isFalse);
      expect(File(pathOf('notes.txt')).readAsStringSync(), 'second edit\n');
      expect((await service.stashCount(repo)).valueOrNull, 1);
    });
  });

  group('divergence and merge', () {
    late Directory tmp;
    late Repository repo;
    final service = GitService();
    const identity = GitIdentity(name: 'Test User', email: 'test@bcode.local');

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('bcode_merge_');
      repo = Repository.init(path: '${tmp.path}/repo');
    });

    tearDown(() {
      repo.free();
      tmp.deleteSync(recursive: true);
    });

    String pathOf(String name) => '${repo.workdir}/$name';

    Future<String> baseBranch() async {
      final current = await service.currentBranch(repo);
      expect(current.isOk, isTrue, reason: current.errorOrNull);
      return current.valueOrNull!;
    }

    Future<Oid> commit(String name, String content, String message) async {
      File(pathOf(name)).writeAsStringSync(content);
      final result = await service.commitAll(repo, message, identity);
      expect(result.isOk, isTrue, reason: result.errorOrNull);
      return repo.head.target;
    }

    test('counts ahead/behind against a remote-tracking ref', () async {
      await commit('shared.txt', 'base', 'base');
      final base = await baseBranch();

      await service.createBranch(repo, 'other');
      await service.switchBranch(repo, 'other');
      final otherOid = await commit('other.txt', 'other', 'other work');

      await service.switchBranch(repo, base);
      Reference.create(
        repo: repo,
        name: 'refs/remotes/origin/$base',
        target: otherOid,
      ).free();

      final behind = await service.divergence(repo, base);
      expect(behind.isOk, isTrue, reason: behind.errorOrNull);
      expect(behind.valueOrNull!.ahead, 0);
      expect(behind.valueOrNull!.behind, 1);
      expect(behind.valueOrNull!.canFastForward, isTrue);

      await commit('master.txt', 'main', 'main work');
      final diverged = await service.divergence(repo, base);
      expect(diverged.valueOrNull!.ahead, 1);
      expect(diverged.valueOrNull!.behind, 1);
      expect(diverged.valueOrNull!.hasDiverged, isTrue);
    });

    test('reports ahead with no remote-tracking ref at all', () async {
      await commit('shared.txt', 'one', 'initial');
      final base = await baseBranch();
      final result = await service.divergence(repo, base);
      expect(result.valueOrNull!.ahead, 1);
      expect(result.valueOrNull!.behind, 0);
    });

    test('merges branches whose files do not overlap', () async {
      await commit('shared.txt', 'base', 'base');
      final base = await baseBranch();

      await service.createBranch(repo, 'other');
      await service.switchBranch(repo, 'other');
      await commit('other.txt', 'other', 'other work');

      await service.switchBranch(repo, base);
      final ours = await commit('main.txt', 'main', 'main work');

      final merged = await service.mergeBranch(repo, 'other', identity);
      expect(merged.isOk, isTrue, reason: merged.errorOrNull);
      expect(File(pathOf('shared.txt')).readAsStringSync(), 'base');
      expect(File(pathOf('main.txt')).readAsStringSync(), 'main');
      expect(File(pathOf('other.txt')).readAsStringSync(), 'other');

      final head = Commit.lookup(repo: repo, oid: repo.head.target);
      expect(head.parents.length, 2);
      expect(head.parents, contains(ours));
    });

    test('stops on overlapping files and changes nothing', () async {
      await commit('shared.txt', 'base', 'base');
      final base = await baseBranch();

      await service.createBranch(repo, 'other');
      await service.switchBranch(repo, 'other');
      await commit('shared.txt', 'other version', 'other edit');

      await service.switchBranch(repo, base);
      final ours = await commit('shared.txt', 'main version', 'main edit');

      final merged = await service.mergeBranch(repo, 'other', identity);

      expect(merged.isOk, isFalse);
      expect(merged.errorOrNull, contains('shared.txt'));
      expect(File(pathOf('shared.txt')).readAsStringSync(), 'main version');
      expect(repo.head.target, ours);
      expect(repo.index.hasConflicts, isFalse);
    });

    test('refuses to merge with uncommitted changes', () async {
      await commit('shared.txt', 'base', 'base');
      final base = await baseBranch();
      await service.createBranch(repo, 'other');
      await service.switchBranch(repo, 'other');
      await commit('other.txt', 'other', 'other work');
      await service.switchBranch(repo, base);
      final ours = await commit('main.txt', 'main', 'main work');

      File(pathOf('main.txt')).writeAsStringSync('uncommitted');
      final merged = await service.mergeBranch(repo, 'other', identity);

      expect(merged.isOk, isFalse);
      expect(merged.errorOrNull, contains('uncommitted'));
      expect(repo.head.target, ours);
      expect(File(pathOf('main.txt')).readAsStringSync(), 'uncommitted');
    });

    test('refuses a merge that would overwrite an untracked file', () async {
      await commit('shared.txt', 'base', 'base');
      final base = await baseBranch();
      await service.createBranch(repo, 'other');
      await service.switchBranch(repo, 'other');
      await commit('theirs.txt', 'from other', 'other work');
      await service.switchBranch(repo, base);
      final ours = await commit('ours.txt', 'ours', 'ours');

      File(pathOf('theirs.txt')).writeAsStringSync('untracked local copy');
      final merged = await service.mergeBranch(repo, 'other', identity);

      expect(merged.isOk, isFalse);
      expect(merged.errorOrNull, contains('untracked file(s)'));
      expect(repo.head.target, ours);
      expect((await service.currentBranch(repo)).valueOrNull, base);
      expect(
        File(pathOf('theirs.txt')).readAsStringSync(),
        'untracked local copy',
      );
    });

    test('merging a missing branch is an Err', () async {
      await commit('shared.txt', 'base', 'base');
      final result = await service.mergeBranch(repo, 'nope', identity);
      expect(result.isOk, isFalse);
      expect(result.errorOrNull, contains('No local or remote branch'));
    });

    test('pull explains divergence against a real remote and merge resolves it',
        () async {
      final remotePath = '${tmp.path}/remote.git';
      Repository.init(path: remotePath, bare: true).free();

      await commit('shared.txt', 'base', 'base');
      final base = await baseBranch();
      Remote.create(repo: repo, name: 'origin', url: remotePath).free();
      Remote.lookup(repo: repo, name: 'origin')
          .push(refspecs: ['refs/heads/$base']);

      final other =
          Repository.clone(url: remotePath, localPath: '${tmp.path}/other');
      File('${other.workdir}/theirs.txt').writeAsStringSync('theirs');
      final index = other.index;
      index.addAll(['*']);
      index.write();
      final signature =
          Signature.create(name: identity.name, email: identity.email);
      Commit.create(
        repo: other,
        updateRef: 'HEAD',
        author: signature,
        committer: signature,
        message: 'theirs',
        tree: Tree.lookup(repo: other, oid: index.writeTree()),
        parents: [Commit.lookup(repo: other, oid: other.head.target)],
      );
      Remote.lookup(repo: other, name: 'origin')
          .push(refspecs: ['refs/heads/$base']);
      other.free();

      final ours = await commit('ours.txt', 'ours', 'ours');
      final headBefore = repo.head.target;

      final pulled = await service.pull(repo, 'token', branch: base);

      expect(pulled.isOk, isFalse);
      expect(pulled.errorOrNull, contains('diverged'));
      expect(pulled.errorOrNull, contains('Nothing was changed'));
      expect(repo.head.target, headBefore);
      expect(File(pathOf('theirs.txt')).existsSync(), isFalse);

      final counts = await service.divergence(repo, base);
      expect(counts.valueOrNull!.ahead, 1);
      expect(counts.valueOrNull!.behind, 1);

      final merged = await service.mergeBranch(repo, 'origin/$base', identity);
      expect(merged.isOk, isTrue, reason: merged.errorOrNull);
      expect(File(pathOf('theirs.txt')).readAsStringSync(), 'theirs');
      expect(File(pathOf('ours.txt')).readAsStringSync(), 'ours');
      expect(repo.head.target, isNot(ours));
    });
  });
}
