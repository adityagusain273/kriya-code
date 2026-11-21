import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:kriya_code/core/archive_extractor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;
  late Directory extractDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('bcode_bomb_test');
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
    final file = File('${tempDir.path}/$name')
      ..writeAsBytesSync(ZipEncoder().encode(archive));
    return file;
  }

  group('compressed container cap', () {
    test('rejects a container larger than the cap, whatever it contains', () async {
      final file = File('${tempDir.path}/huge.zip');
      // A seek plus one byte extends the file length without paying for the
      // zero bytes in between, so the cap can be hit on length alone.
      final handle = await file.open(mode: FileMode.write);
      await handle.setPosition(ArchiveExtractor.maxCompressedBytes);
      await handle.writeByte(0);
      await handle.close();

      await expectLater(
        ArchiveExtractor.extract(file, extractDir.path),
        throwsA(isA<ArchiveExtractionException>()),
      );
      expect(Directory(extractDir.path).existsSync(), isFalse);
    });

    test('accepts a normal-sized zip', () async {
      final zip = await writeZip('ok.zip', [
        ArchiveFile('hello.txt', 5, 'world'.codeUnits),
      ]);

      await ArchiveExtractor.extract(zip, extractDir.path);

      expect(File('${extractDir.path}/hello.txt').readAsStringSync(), 'world');
    });
  });

  group('declared entry size', () {
    test('refuses an entry declaring more than the budget before reading it',
        () async {
      final zip = await writeZip('declared.zip', [
        ArchiveFile('big.bin', 600 * 1024 * 1024, List<int>.filled(16, 0x41)),
      ]);

      await expectLater(
        ArchiveExtractor.extract(zip, extractDir.path),
        throwsA(isA<ArchiveExtractionException>()),
      );
      expect(Directory(extractDir.path).existsSync(), isFalse);
    });
  });

  group('decompression bombs', () {
    test('a real gzip bomb is refused while still decompressing', () async {
      // Expands past the total budget from a tiny compressed file. The
      // intermediate decompressed stream is capped, so the refusal must land
      // before any entry is parsed or written.
      final bomb = File('${tempDir.path}/bomb.tar.gz')
        ..writeAsBytesSync(
          GZipCodec(level: ZLibOption.minLevel)
              .encode(Uint8List(520 * 1024 * 1024)),
        );

      await expectLater(
        ArchiveExtractor.extract(bomb, extractDir.path),
        throwsA(isA<ArchiveExtractionException>()),
      );
      expect(Directory(extractDir.path).existsSync(), isFalse);
    });

    test('extracts a real bzip2 tar through the streaming path', () async {
      const body = 'print(1)\n';
      final archive = Archive()
        ..add(ArchiveFile('main.py', body.length, body.codeUnits));
      final file = File('${tempDir.path}/proj.tar.bz2')
        ..writeAsBytesSync(BZip2Encoder().encode(TarEncoder().encode(archive)));

      await ArchiveExtractor.extract(file, extractDir.path);

      expect(File('${extractDir.path}/main.py').readAsStringSync(), body);
    });
  });
}
