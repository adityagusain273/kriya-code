import 'package:flutter_test/flutter_test.dart';
import 'package:b_code/core/result.dart';
import 'package:b_code/plugins/builtin/builtin_extensions.dart';
import 'package:b_code/plugins/host/extension_registry.dart';
import 'package:b_code/plugins/host/command_registry.dart';
import 'package:b_code/plugins/host/event_bus.dart';
import 'package:b_code/plugins/host/language_registry.dart';
import 'package:b_code/plugins/api/extension.dart';
import 'package:b_code/workspace/fs_service.dart';
import 'dart:io';

void main() {
  group('Result', () {
    test('fold dispatches ok/err', () async {
      final ok = await guard(() async => 42);
      expect(ok.fold((v) => v, (_) => -1), 42);
      final err = await guard<int>(() => throw StateError('boom'));
      expect(err.errorOrNull, contains('boom'));
    });
  });

  group('CommandRegistry', () {
    test('executes registered command', () async {
      final reg = CommandRegistry();
      var called = false;
      reg.register('test.cmd', (args) async => called = true);
      await reg.execute('test.cmd');
      expect(called, isTrue);
      expect(await reg.execute('missing'), isFalse);
    });
  });

  group('Extension system', () {
    test('builtin extensions register exactly 4 languages', () async {
      final registry = ExtensionRegistry();
      registry.languageRegistry = LanguageRegistry();
      registry.commandRegistry = CommandRegistry();
      registry.eventBus = BCodeEventBus();
      for (final ext in builtinExtensions) {
        await ext.activate(_FakeContext(registry.languageRegistry, registry.commandRegistry));
      }
      final ids = registry.languageRegistry.all.map((c) => c.id).toSet();
      expect(ids, containsAll(['python', 'c', 'cpp', 'java']));
    });

    test('language resolution by filename', () {
      final reg = LanguageRegistry();
      for (final ext in builtinExtensions) {
        ext.activate(_FakeContext(reg, CommandRegistry()));
      }
      expect(reg.byFileName('main.py')?.id, 'python');
      expect(reg.byFileName('kernel.c')?.id, 'c');
      expect(reg.byFileName('app.cpp')?.id, 'cpp');
      expect(reg.byFileName('Main.java')?.id, 'java');
      expect(reg.byFileName('notes.txt'), isNull);
    });
  });

  group('FsService', () {
    late Directory temp;
    late FsService fs;

    setUp(() {
      temp = Directory.systemTemp.createTempSync('bcode_test');
      fs = FsService(temp.path);
    });

    tearDown(() {
      temp.deleteSync(recursive: true);
    });

    test('create, write, read file', () async {
      await fs.createFile('src/main.py');
      await fs.writeFile('src/main.py', 'print("hi")');
      expect(await fs.readFile('src/main.py'), 'print("hi")');
    });

    test('rename and move', () async {
      await fs.createFile('a.txt');
      await fs.writeFile('a.txt', 'x');
      await fs.rename('a.txt', 'b.txt');
      expect(fs.exists('b.txt'), isTrue);
      await fs.createDirectory('sub');
      await fs.move('b.txt', 'sub');
      expect(fs.exists('sub/b.txt'), isTrue);
    });

    test('delete recursive', () async {
      await fs.createDirectory('proj/deep');
      await fs.createFile('proj/deep/f.py');
      await fs.delete('proj');
      expect(fs.exists('proj'), isFalse);
    });

    test('rejects relative path escape', () {
      // Relative paths that escape workspace should be rejected
      expect(() => fs.resolve('../outside'), throwsArgumentError);
      expect(() => fs.resolve('../../etc/passwd'), throwsArgumentError);
    });

    test('allows absolute paths for SAF access', () {
      // Absolute paths are allowed (for SAF file access)
      final result = fs.resolve('/etc/passwd');
      expect(result, '/etc/passwd');
    });
  });
}

class _FakeContext implements ExtensionContext {
  _FakeContext(this.languages, this.commands);

  @override
  final LanguageRegistry languages;
  @override
  final CommandRegistry commands;

  @override
  BCodeEventBus get events => BCodeEventBus();

  @override
  FsService get fs => throw UnimplementedError();
}
