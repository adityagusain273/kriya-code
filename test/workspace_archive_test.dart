import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:b_code/workspace/workspace_archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;
  late Directory root;
  late File output;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('bcode_workspace_zip');
    root = Directory(p.join(temp.path, 'workspace'))..createSync(recursive: true);
    output = File(p.join(temp.path, 'workspace.zip'));
  });

  tearDown(() => temp.deleteSync(recursive: true));

  test('zips nested directories, empty directories and a large file', () async {
    File(p.join(root.path, 'src/main.py'))
      ..createSync(recursive: true)
      ..writeAsStringSync('print("hi")');
    File(p.join(root.path, 'src/deep/notes.txt'))
      ..createSync(recursive: true)
      ..writeAsStringSync('nested');
    Directory(p.join(root.path, 'empty-dir')).createSync();
    final large = File(p.join(root.path, 'assets/big.bin'));
    large.createSync(recursive: true);
    final largeBytes = List<int>.generate(1024 * 1024 + 17, (i) => i % 251);
    large.writeAsBytesSync(largeBytes);

    final progress = <(int, int)>[];
    final result = await WorkspaceArchive().build(
      root,
      output,
      onProgress: (files, bytes) => progress.add((files, bytes)),
    );

    expect(result.files, 3);
    expect(result.bytes, largeBytes.length + 'print("hi")'.length + 'nested'.length);
    expect(progress.last.$1, 3);
    expect(File(p.join(root.path, 'assets/big.bin')).lengthSync(),
        largeBytes.length);

    final archive = ZipDecoder().decodeBytes(output.readAsBytesSync());
    final names = archive.files.map((file) => file.name).toSet();

    expect(names, containsAll(<String>[
      'workspace/',
      'src/',
      'src/main.py',
      'src/deep/',
      'src/deep/notes.txt',
      'empty-dir/',
      'assets/',
      'assets/big.bin',
    ]));

    final readme = archive.findFile('src/main.py');
    expect(readme, isNotNull);
    expect(utf8.decode(readme!.content as List<int>), 'print("hi")');

    final big = archive.findFile('assets/big.bin');
    expect(big!.content, hasLength(1024 * 1024 + 17));
  });

  test('an empty directory survives a round trip', () async {
    Directory(p.join(root.path, 'nothing/here')).createSync(recursive: true);

    final result = await WorkspaceArchive().build(root, output);

    expect(result.files, 0);
    expect(result.bytes, 0);

    final archive = ZipDecoder().decodeBytes(output.readAsBytesSync());
    expect(archive.findFile('nothing/here/'), isNotNull);
  });

  test('skipping .git leaves the rest of the tree', () async {
    File(p.join(root.path, '.git/config'))
      ..createSync(recursive: true)
      ..writeAsStringSync('core.repositoryformatversion = 0');
    File(p.join(root.path, 'main.py')).writeAsStringSync('print(1)');

    final result = await WorkspaceArchive().build(
      root,
      output,
      include: (path) => !path.split('/').contains('.git'),
    );

    expect(result.files, 1);

    final archive = ZipDecoder().decodeBytes(output.readAsBytesSync());
    expect(archive.findFile('main.py'), isNotNull);
    expect(archive.findFile('.git/config'), isNull);
    expect(archive.findFile('.git/'), isNull);
  });

  test('an excluded directory leaves no empty entry behind', () async {
    File(p.join(root.path, '.git/config'))
      ..createSync(recursive: true)
      ..writeAsStringSync('[core]');
    File(p.join(root.path, 'src/a.txt'))
      ..createSync(recursive: true)
      ..writeAsStringSync('a');

    await WorkspaceArchive().build(
      root,
      output,
      include: (path) => !path.split('/').contains('.git'),
    );

    final archive = ZipDecoder().decodeBytes(output.readAsBytesSync());
    expect(archive.findFile('.git/'), isNull);
    expect(archive.findFile('src/'), isNotNull);
    expect(archive.findFile('src/a.txt'), isNotNull);
  });

  test('does not include its own output file in the archive', () async {
    final inside = File(p.join(root.path, 'workspace.zip'));
    File(p.join(root.path, 'main.py')).writeAsStringSync('print(1)');

    await WorkspaceArchive().build(root, inside);
    final first = ZipDecoder().decodeBytes(inside.readAsBytesSync());
    expect(first.findFile('workspace.zip'), isNull);

    await WorkspaceArchive().build(root, inside);
    final second = ZipDecoder().decodeBytes(inside.readAsBytesSync());
    expect(second.findFile('workspace.zip'), isNull);
    expect(second.findFile('main.py'), isNotNull);
  });
}