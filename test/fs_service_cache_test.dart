import 'dart:io';

import 'package:kriya_code/workspace/fs_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late FsService fs;

  setUp(() {
    root = Directory.systemTemp.createTempSync('bcode_fs_cache_');
    fs = FsService(root.path);
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  test('listing is cached until a mutation or an explicit refresh', () async {
    await fs.writeFile('a.txt', 'a');

    final first = await fs.list('.');
    expect(first.map((e) => e.name), contains('a.txt'));

    // Written behind the service, as a git checkout or another app would.
    File('${root.path}/b.txt').writeAsStringSync('b');

    final cached = await fs.list('.');
    expect(cached.map((e) => e.name), isNot(contains('b.txt')));

    final refreshed = await fs.list('.', refresh: true);
    expect(refreshed.map((e) => e.name), contains('b.txt'));
  });

  test('service mutations invalidate the listing', () async {
    await fs.list('.');
    await fs.createFile('created.txt');

    final listed = await fs.list('.');
    expect(listed.map((e) => e.name), contains('created.txt'));
  });

  test('delete invalidates the listing', () async {
    await fs.writeFile('a.txt', 'a');
    await fs.list('.');
    await fs.delete('a.txt');

    expect(
      (await fs.list('.')).map((e) => e.name),
      isNot(contains('a.txt')),
    );
  });

  test('hidden files are opt-in and .git stays out', () async {
    await fs.writeFile('.env', 'TOKEN=1');
    Directory('${root.path}/.git').createSync();
    await fs.writeFile('visible.txt', 'v');

    var names = (await fs.list('.')).map((e) => e.name);
    expect(names, contains('visible.txt'));
    expect(names, isNot(contains('.env')));

    fs.showHidden = true;
    names = (await fs.list('.')).map((e) => e.name);
    expect(names, contains('.env'));
    expect(names, isNot(contains('.git')));
  });

  test('build and dependency directories stay out of the tree', () async {
    for (final name in [
      'node_modules',
      'build',
      'dist',
      '.cache',
      '.next',
      'src',
    ]) {
      Directory('${root.path}/$name').createSync();
    }

    final names = (await fs.list('.')).map((e) => e.name);
    expect(names, contains('src'));
    expect(names, isNot(contains('node_modules')));
    expect(names, isNot(contains('build')));
    expect(names, isNot(contains('dist')));

    // The dot-directories stay hidden even when dotfiles are opted in.
    fs.showHidden = true;
    final visible = (await fs.list('.')).map((e) => e.name);
    expect(visible, isNot(contains('.cache')));
    expect(visible, isNot(contains('.next')));
  });

  test('binary files are refused with a readable message', () async {
    File('${root.path}/image.png').writeAsBytesSync([0x89, 0x50, 0x4E, 0x47, 0]);

    await expectLater(
      fs.readFile('image.png'),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('binary'),
        ),
      ),
    );
  });

  test('invalid UTF-8 is refused instead of throwing FormatException', () async {
    File('${root.path}/bad.txt').writeAsBytesSync([0xFF, 0xFE, 0x41]);

    await expectLater(fs.readFile('bad.txt'), throwsA(isA<StateError>()));
  });
}
