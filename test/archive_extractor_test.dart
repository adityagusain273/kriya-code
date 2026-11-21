import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:kriya_code/core/archive_extractor.dart';
import 'package:flutter_test/flutter_test.dart';

ArchiveFile _symlink(String name, String target) {
  final file = ArchiveFile(name, 0, const []);
  file.symbolicLink = target;
  return file;
}

void main() {
  late Directory tempDir;
  late Directory extractDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('bcode_zip_test');
    extractDir = Directory('${tempDir.path}/out');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<File> writeZip(String name, List<ArchiveFile> entries) async {
    final archive = Archive();
    for (final entry in entries) {
      archive.add(entry);
    }
    final bytes = ZipEncoder().encode(archive);
    final file = File('${tempDir.path}/$name')..writeAsBytesSync(bytes);
    return file;
  }

  test('extracts a normal archive', () async {
    final zip = await writeZip('ok.zip', [
      ArchiveFile('hello.txt', 5, 'world'.codeUnits),
      ArchiveFile('nested/deep.txt', 2, 'hi'.codeUnits),
    ]);

    await ArchiveExtractor.extract(zip, extractDir.path);

    expect(File('${extractDir.path}/hello.txt').readAsStringSync(), 'world');
    expect(File('${extractDir.path}/nested/deep.txt').readAsStringSync(), 'hi');
  });

  test('rejects a ../ traversal entry', () async {
    final victim = File('${tempDir.path}/victim.txt')
      ..writeAsStringSync('original');

    final zip = await writeZip('evil.zip', [
      ArchiveFile('../victim.txt', 6, 'PWNED!'.codeUnits),
    ]);

    await expectLater(
      ArchiveExtractor.extract(zip, extractDir.path),
      throwsA(isA<ArchiveExtractionException>()),
    );

    expect(victim.readAsStringSync(), 'original');
  });

  test('rejects a deep traversal entry', () async {
    final zip = await writeZip('deep.zip', [
      ArchiveFile('../../../../databases/app.db', 1, [0]),
    ]);

    await expectLater(
      ArchiveExtractor.extract(zip, extractDir.path),
      throwsA(isA<ArchiveExtractionException>()),
    );
  });

  test('rejects an absolute entry name', () async {
    final zip = await writeZip('abs.zip', [
      ArchiveFile('/data/data/com.bcode.editor/shared_prefs/x.xml', 1, [0]),
    ]);

    await expectLater(
      ArchiveExtractor.extract(zip, extractDir.path),
      throwsA(isA<ArchiveExtractionException>()),
    );
  });

  test('rejects a sibling directory sharing a name prefix', () async {
    // /tmp/x/out-secret must not be reachable while extracting into /tmp/x/out.
    // A string prefix check would have allowed this.
    Directory('${extractDir.path}-secret').createSync(recursive: true);

    final zip = await writeZip('prefix.zip', [
      ArchiveFile('../out-secret/leak.txt', 4, 'leak'.codeUnits),
    ]);

    await expectLater(
      ArchiveExtractor.extract(zip, extractDir.path),
      throwsA(isA<ArchiveExtractionException>()),
    );

    expect(
      File('${extractDir.path}-secret/leak.txt').existsSync(),
      isFalse,
    );
  });

  test('validateEntryName rejects traversal and absolute names', () {
    expect(
      () => ArchiveExtractor.validateEntryName('/root', '../escape.txt'),
      throwsA(isA<ArchiveExtractionException>()),
    );
    expect(
      () => ArchiveExtractor.validateEntryName('/root', 'a/../../escape.txt'),
      throwsA(isA<ArchiveExtractionException>()),
    );
    expect(
      () => ArchiveExtractor.validateEntryName('/root', '/etc/passwd'),
      throwsA(isA<ArchiveExtractionException>()),
    );
    expect(
      () => ArchiveExtractor.validateEntryName('/root', r'..\escape.txt'),
      throwsA(isA<ArchiveExtractionException>()),
    );
    expect(
      () => ArchiveExtractor.validateEntryName('/root', ''),
      throwsA(isA<ArchiveExtractionException>()),
    );
  });

  test('validateEntryName accepts legitimate nested names', () {
    expect(
      ArchiveExtractor.validateEntryName('/root', 'a/b/c.txt'),
      p.normalize('/root/a/b/c.txt'),
    );
    expect(
      ArchiveExtractor.validateEntryName('/root', 'c.txt'),
      p.normalize('/root/c.txt'),
    );
  });

  test('a symlink entry is rejected', () {
    final entry = _symlink('link.txt', '../../../../etc/passwd');
    expect(entry.isSymbolicLink, isTrue);
    // The extract loop refuses these before touching validateEntryName.
    expect(entry.isDirectory, isFalse);
  });

  test('rejects an entry count over the cap', () async {
    final entries = List.generate(
      ArchiveExtractor.maxEntries + 1,
      (i) => ArchiveFile('f$i.txt', 1, [0]),
    );
    final zip = await writeZip('bomb.zip', entries);

    await expectLater(
      ArchiveExtractor.extract(zip, extractDir.path),
      throwsA(isA<ArchiveExtractionException>()),
    );
  }, timeout: const Timeout.factor(4));

  test('a traversal entry after a good entry still aborts cleanly', () async {
    final zip = await writeZip('mixed.zip', [
      ArchiveFile('fine.txt', 4, 'okay'.codeUnits),
      ArchiveFile('../escape.txt', 3, 'bad'.codeUnits),
    ]);

    await expectLater(
      ArchiveExtractor.extract(zip, extractDir.path),
      throwsA(isA<ArchiveExtractionException>()),
    );

    expect(
      File('${tempDir.path}/escape.txt').existsSync(),
      isFalse,
      reason: 'nothing may be written outside the target directory',
    );
  });

  group('formats', () {
    test('isArchiveName recognises the containers we can unpack', () {
      expect(ArchiveExtractor.isArchiveName('app.zip'), isTrue);
      expect(ArchiveExtractor.isArchiveName('app.ZIP'), isTrue);
      expect(ArchiveExtractor.isArchiveName('app.tar'), isTrue);
      expect(ArchiveExtractor.isArchiveName('app.tar.gz'), isTrue);
      expect(ArchiveExtractor.isArchiveName('app.tgz'), isTrue);
      expect(ArchiveExtractor.isArchiveName('app.tar.bz2'), isTrue);
      expect(ArchiveExtractor.isArchiveName('main.dart'), isFalse);
      expect(ArchiveExtractor.isArchiveName('notes.txt'), isFalse);
      expect(ArchiveExtractor.isArchiveName('zip'), isFalse);
    });

    test('formatForName prefers the longest suffix', () {
      expect(ArchiveExtractor.formatForName('a.tar.gz'), ArchiveFormat.tarGzip);
      expect(ArchiveExtractor.formatForName('a.tar'), ArchiveFormat.tar);
      expect(ArchiveExtractor.formatForName('a.zip'), ArchiveFormat.zip);
      expect(ArchiveExtractor.formatForName('a.dart'), isNull);
    });

    test('folderNameFor strips the archive suffix', () {
      expect(ArchiveExtractor.folderNameFor('my-project.zip'), 'my-project');
      expect(ArchiveExtractor.folderNameFor('my-project.tar.gz'), 'my-project');
      expect(ArchiveExtractor.folderNameFor('/a/b/my.tgz'), 'my');
      expect(ArchiveExtractor.folderNameFor('..'), 'extracted');
      expect(ArchiveExtractor.folderNameFor('.zip'), 'extracted');
    });

    test('detectFormat reads magic bytes, not the name', () {
      expect(ArchiveExtractor.detectFormat([0x50, 0x4B, 0x03, 0x04]),
          ArchiveFormat.zip);
      expect(ArchiveExtractor.detectFormat([0x1F, 0x8B, 0x08]),
          ArchiveFormat.tarGzip);
      expect(ArchiveExtractor.detectFormat(utf8.encode('BZh9')), ArchiveFormat.tarBzip2);
      final tarHead = List<int>.filled(262, 0);
      tarHead.setRange(257, 262, 'ustar'.codeUnits);
      expect(ArchiveExtractor.detectFormat(tarHead), ArchiveFormat.tar);
      expect(ArchiveExtractor.detectFormat(utf8.encode('not an archive at all')),
          isNull);
    });
  });

  group('tar', () {
    Future<File> writeTar(String name, List<ArchiveFile> entries) async {
      final archive = Archive();
      for (final e in entries) {
        archive.add(e);
      }
      final file = File('${tempDir.path}/$name')
        ..writeAsBytesSync(TarEncoder().encode(archive));
      return file;
    }

    test('extracts a plain tar', () async {
      final tar = await writeTar('ok.tar', [
        ArchiveFile('hello.txt', 5, 'world'.codeUnits),
        ArchiveFile('nested/deep.txt', 2, 'hi'.codeUnits),
      ]);

      await ArchiveExtractor.extract(tar, extractDir.path);

      expect(File('${extractDir.path}/hello.txt').readAsStringSync(), 'world');
      expect(File('${extractDir.path}/nested/deep.txt').readAsStringSync(), 'hi');
    });

    test('extracts a gzipped tar', () async {
      const body = 'print(1)\n\n';
      final archive = Archive()
        ..add(ArchiveFile('main.py', body.length, body.codeUnits));
      final gz = GZipEncoder().encode(TarEncoder().encode(archive));
      final tar = File('${tempDir.path}/proj.tar.gz')..writeAsBytesSync(gz);

      await ArchiveExtractor.extract(tar, extractDir.path);

      expect(File('${extractDir.path}/main.py').readAsStringSync(), 'print(1)\n\n');
    });

    test('a traversal entry in a tar is refused', () async {
      final victim = File('${tempDir.path}/victim.txt')
        ..writeAsStringSync('original');
      final tar = await writeTar('evil.tar', [
        ArchiveFile('../victim.txt', 6, 'PWNED!'.codeUnits),
      ]);

      await expectLater(
        ArchiveExtractor.extract(tar, extractDir.path),
        throwsA(isA<ArchiveExtractionException>()),
      );
      expect(victim.readAsStringSync(), 'original');
    });

    test('a refused tar leaves no partial folder behind', () async {
      final tar = await writeTar('partial.tar', [
        ArchiveFile('fine.txt', 4, 'okay'.codeUnits),
        ArchiveFile('../escape.txt', 3, 'bad'.codeUnits),
      ]);

      await expectLater(
        ArchiveExtractor.extract(tar, extractDir.path),
        throwsA(isA<ArchiveExtractionException>()),
      );

      expect(
        Directory(extractDir.path).existsSync(),
        isFalse,
        reason: 'a half-extracted project looks usable but is missing files',
      );
    });

    test('a refused zip leaves no partial folder behind', () async {
      final zip = await writeZip('partial.zip', [
        ArchiveFile('fine.txt', 4, 'okay'.codeUnits),
        ArchiveFile('../escape.txt', 3, 'bad'.codeUnits),
      ]);

      await expectLater(
        ArchiveExtractor.extract(zip, extractDir.path),
        throwsA(isA<ArchiveExtractionException>()),
      );

      expect(Directory(extractDir.path).existsSync(), isFalse);
    });

    test('reports progress and finishes with the real totals', () async {
      final zip = await writeZip('progress.zip', [
        ArchiveFile('a.txt', 1, [0]),
        ArchiveFile('b.txt', 1, [0]),
      ]);
      final seen = <int>[];

      await ArchiveExtractor.extractWithProgress(zip, extractDir.path,
          (entries, bytes) => seen.add(entries));

      expect(seen, isNotEmpty);
      expect(seen.last, 2);
    });

    test('an unrecognised container is reported, not half-written', () async {
      final bogus = File('${tempDir.path}/notes.zip')
        ..writeAsStringSync('this is just a text file');

      await expectLater(
        ArchiveExtractor.extract(bogus, extractDir.path),
        throwsA(isA<ArchiveExtractionException>()),
      );
      expect(Directory(extractDir.path).existsSync(), isFalse);
    });
  });
}
