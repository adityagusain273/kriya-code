import 'dart:io';

import 'package:b_code/github/git_service.dart';
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
}
