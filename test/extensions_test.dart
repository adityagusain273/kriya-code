import 'package:flutter_test/flutter_test.dart';
import 'package:b_code/core/di.dart';
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

    test('loadAll fills the registry consumers already hold', () async {
      final temp = Directory.systemTemp.createTempSync('bcode_registry');
      addTearDown(() => temp.deleteSync(recursive: true));
      sl.reset();
      sl.registerSingleton<FsService>(FsService(temp.path));
      addTearDown(sl.reset);

      final registry = ExtensionRegistry();
      // HighlightService is built before the deferred load runs, so it holds
      // this instance and loadAll must fill it rather than swap it out.
      final held = registry.languageRegistry;
      expect(held.all, isEmpty);

      await registry.loadAll(builtinExtensions);

      expect(registry.languageRegistry, same(held));
      expect(held.byFileName('main.py')?.id, 'python');
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
      expect(() => fs.resolve('../outside'), throwsArgumentError);
      expect(() => fs.resolve('../../etc/passwd'), throwsArgumentError);
    });

    test('resolves the workspace root itself', () {
      // Every directory listing goes through this. p.isWithin(root, root) is
      // false, so this used to throw and the explorer rendered nothing.
      expect(fs.resolve('.'), fs.rootPath);
      expect(fs.resolve(''), fs.rootPath);
    });

    test('rejects absolute paths outside the workspace', () {
      // An absolute path used to bypass containment entirely, which is how the
      // New File dialog could create and truncate files anywhere on the device.
      expect(() => fs.resolve('/etc/passwd'), throwsArgumentError);
      expect(
        () => fs.resolve('/data/data/com.bcode.editor/shared_prefs/x.xml'),
        throwsArgumentError,
      );
    });

    test('rejects absolute paths that traverse out of the workspace', () {
      expect(() => fs.resolve('${fs.rootPath}/../secrets'), throwsArgumentError);
    });

    test('rejects symlinked path components', () async {
      final outside = await Directory.systemTemp.createTemp('bcode_outside');
      addTearDown(() => outside.delete(recursive: true));
      await File('${outside.path}/secret.txt').writeAsString('nope');

      final link = Link('${fs.rootPath}/escape');
      await link.create(outside.path);

      expect(() => fs.resolve('escape/secret.txt'), throwsArgumentError);
    });

    test('resolveExternal refuses paths outside the workspace', () {
      expect(() => fs.resolveExternal('/etc/passwd'), throwsArgumentError);
      expect(fs.resolveExternal('${fs.rootPath}/a.txt'), '${fs.rootPath}/a.txt');
    });

    test('writeFile replaces atomically and leaves no temp file', () async {
      await fs.writeFile('atomic.txt', 'hello');
      expect(await fs.readFile('atomic.txt'), 'hello');

      await fs.writeFile('atomic.txt', 'goodbye');
      expect(await fs.readFile('atomic.txt'), 'goodbye');

      final leftovers = await Directory(fs.rootPath)
          .list()
          .where((e) => e.path.endsWith('.bcode-tmp'))
          .toList();
      expect(leftovers, isEmpty);
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
