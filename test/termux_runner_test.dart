import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:b_code/core/constants.dart';
import 'package:b_code/execution/local/local_runner.dart';
import 'package:b_code/execution/models.dart';
import 'package:b_code/execution/runner_service.dart';
import 'package:b_code/execution/termux_runner.dart';
import 'package:b_code/plugins/api/run_config.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(AppConstants.termuxChannel);
  final log = <MethodCall>[];

  setUp(() {
    log.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      log.add(call);
      switch (call.method) {
        case 'isInstalled':
          return true;
        case 'isAllowed':
          return true;
        case 'openTermux':
          return true;
        case 'runCommand':
          return {
            'success': true,
            'stdout': 'output-ok',
            'stderr': '',
            'exitCode': 0,
          };
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('TermuxRunner checks availability and runs commands', () async {
    final available = await TermuxRunner.checkAvailability();
    expect(available, isTrue);

    final res = await TermuxRunner.runCommand(
      command: '/bin/uname',
      args: ['-a'],
    );
    expect(res.success, isTrue);
    expect(res.stdout, 'output-ok');
    expect(res.exitCode, 0);

    expect(log.length, 3);
    expect(log[0].method, 'isInstalled');
    expect(log[1].method, 'isAllowed');
    expect(log[2].method, 'runCommand');
  });

  test('RunnerService stages private storage files for Termux execution', () async {
    final runner = RunnerService(local: LocalRunner());
    const request = RunRequest(
      mainFile: 'hello.py',
      source: 'print("hello world")',
    );
    const config = RunConfig(
      local: LocalTarget(
        runtimeId: 'python-test',
        runArgv: ['{runtimePath}/bin/python3', '{file}'],
      ),
    );

    await runner.run(
      request: request,
      config: config,
      workDir: '/data/user/0/com.bcode.editor/app_flutter/projects/demo',
    );

    final runCall = log.firstWhere((call) => call.method == 'runCommand');
    final args = runCall.arguments as Map<dynamic, dynamic>;

    expect(args['command'], '/data/data/com.termux/files/usr/bin/bash');
    expect(args['stdin'], isNull);
    expect(args['workDir'], '/data/data/com.termux/files/home');

    final cmdArgs = (args['args'] as List).cast<String>();
    expect(cmdArgs[0], '-c');
    expect(cmdArgs[1], contains(RegExp(r'mkdir -p /data/data/com\.termux/files/home/\.bcode/cache/[A-Za-z0-9._-]+')));
    expect(cmdArgs[1], contains('base64 -d'));
    expect(cmdArgs[1], contains('cd /data/data/com.termux/files/home/.bcode/cache/'));
    expect(cmdArgs[1], contains(RegExp(r'"/data/data/com\.termux/files/usr/bin/python3" "/data/data/com\.termux/files/home/\.bcode/cache/demo-[0-9a-f-]+/hello\.py"')));
    expect(cmdArgs[2], '--');
    expect(cmdArgs[3], 'hello.py');
  });

  test('RunnerService forwards args and stdin, and chains buildArgv and runArgv', () async {
    final runner = RunnerService(local: LocalRunner());
    const request = RunRequest(
      mainFile: 'main.c',
      source: 'int main() { return 0; }',
      stdin: 'user input line\n',
      args: ['--verbose', 'arg with spaces'],
    );
    const config = RunConfig(
      local: LocalTarget(
        runtimeId: 'clang-test',
        buildArgv: ['{runtimePath}/bin/clang', '{file}', '-o', '{outDir}/{name}.out'],
        runArgv: ['{outDir}/{name}.out'],
      ),
    );

    await runner.run(
      request: request,
      config: config,
      workDir: '/data/user/0/com.bcode.editor/app_flutter/projects/c_demo',
    );

    final runCall = log.firstWhere((call) => call.method == 'runCommand');
    final args = runCall.arguments as Map<dynamic, dynamic>;

    expect(args['command'], '/data/data/com.termux/files/usr/bin/bash');
    expect(args['stdin'], 'user input line\n');
    expect(args['workDir'], '/data/data/com.termux/files/home');

    final cmdArgs = (args['args'] as List).cast<String>();
    expect(cmdArgs[0], '-c');
    expect(cmdArgs[1], contains(RegExp(r'mkdir -p /data/data/com\.termux/files/home/\.bcode/cache/[A-Za-z0-9._-]+')));
    expect(cmdArgs[1], contains('base64 -d'));
    expect(cmdArgs[1], contains('"/data/data/com.termux/files/usr/bin/clang"'));
    expect(cmdArgs[1], contains(RegExp(r'"/data/data/com\.termux/files/home/\.bcode/cache/c_demo-[0-9a-f-]+/main\.out"')));
    expect(cmdArgs[1], contains('"--verbose" "arg with spaces"'));
    expect(cmdArgs[2], '--');
    expect(cmdArgs[3], 'main.c');
  });

  test('RunnerService archives and synchronizes multi-file project with tar to Termux', () async {
    final tempDir = await Directory.systemTemp.createTemp('bcode_test_proj_');
    try {
      final helperFile = File(p.join(tempDir.path, 'helper.h'));
      await helperFile.writeAsString('int add(int a, int b) { return a + b; }');

      final runner = RunnerService(local: LocalRunner());
      const request = RunRequest(
        mainFile: 'main.c',
        source: '#include "helper.h"\nint main() { return add(2, 3); }',
      );
      const config = RunConfig(
        local: LocalTarget(
          runtimeId: 'clang',
          buildArgv: ['{runtimePath}/bin/clang', '{file}', '-o', '{outDir}/{name}.out'],
          runArgv: ['{outDir}/{name}.out'],
        ),
      );

      await runner.run(
        request: request,
        config: config,
        workDir: tempDir.path,
      );

      final runCall = log.firstWhere((call) => call.method == 'runCommand');
      final args = runCall.arguments as Map<dynamic, dynamic>;
      final cmdArgs = (args['args'] as List).cast<String>();

      expect(cmdArgs[1], contains('tar -xz -C /data/data/com.termux/files/home/.bcode/cache'));
      expect(cmdArgs[1], contains('cd /data/data/com.termux/files/home/.bcode/cache'));
      expect(cmdArgs[1], contains('"/data/data/com.termux/files/usr/bin/clang"'));
    } finally {
      await tempDir.delete(recursive: true);
    }
  });

  test('TermuxRunner.openTermux invokes platform method', () async {
    final opened = await TermuxRunner.openTermux();
    expect(opened, isTrue);
    expect(log.any((call) => call.method == 'openTermux'), isTrue);
  });

  test('RunnerService preserves subfolder relative paths during tar staging', () async {
    final tempDir = await Directory.systemTemp.createTemp('bcode_subfolder_proj_');
    try {
      final srcDir = Directory(p.join(tempDir.path, 'src'))..createSync(recursive: true);
      final incDir = Directory(p.join(tempDir.path, 'include'))..createSync(recursive: true);
      final header = File(p.join(incDir.path, 'lib.h'));
      await header.writeAsString('#define VALUE 100');

      final runner = RunnerService(local: LocalRunner());
      final request = RunRequest(
        mainFile: p.join(srcDir.path, 'entry.c'),
        source: '#include "include/lib.h"\nint main() { return VALUE; }',
      );
      const config = RunConfig(
        local: LocalTarget(
          runtimeId: 'clang',
          buildArgv: ['{runtimePath}/bin/clang', '{file}', '-o', '{outDir}/{name}.out'],
          runArgv: ['{outDir}/{name}.out'],
        ),
      );

      await runner.run(
        request: request,
        config: config,
        workDir: tempDir.path,
      );

      final runCall = log.firstWhere((call) => call.method == 'runCommand');
      final args = runCall.arguments as Map<dynamic, dynamic>;
      final cmdArgs = (args['args'] as List).cast<String>();

      expect(cmdArgs[1], contains(RegExp(r'"/data/data/com\.termux/files/home/\.bcode/cache/[A-Za-z0-9._-]+/src/entry\.c"')));
      expect(cmdArgs[1], contains(RegExp(r'"/data/data/com\.termux/files/home/\.bcode/cache/[A-Za-z0-9._-]+/entry\.out"')));
      expect(cmdArgs[3], 'src/entry.c');
    } finally {
      await tempDir.delete(recursive: true);
    }
  });

  test('web project staging prunes node_modules and keeps package.json', () async {
    final tempDir = await Directory.systemTemp.createTemp('bcode_web_proj_');
    try {
      File(p.join(tempDir.path, 'package.json'))
          .writeAsStringSync('{"name":"demo","scripts":{"dev":"vite"}}');
      File(p.join(tempDir.path, 'index.js')).writeAsStringSync('console.log("hi")');
      final dependency = File(p.join(tempDir.path, 'node_modules/left-pad/index.js'));
      dependency.createSync(recursive: true);
      dependency.writeAsStringSync(List.filled(4096, 'x').join());
      Directory(p.join(tempDir.path, 'dist')).createSync(recursive: true);
      File(p.join(tempDir.path, 'dist/bundle.js')).writeAsStringSync('built');

      final runner = RunnerService(local: LocalRunner());
      const request = RunRequest(mainFile: 'index.js', source: 'console.log("hi")');
      const config = RunConfig(
        local: LocalTarget(
          runtimeId: 'nodejs',
          runArgv: ['{runtimePath}/bin/node', '{file}'],
        ),
      );

      await runner.run(request: request, config: config, workDir: tempDir.path);

      final runCall = log.firstWhere((call) => call.method == 'runCommand');
      final cmdArgs = ((runCall.arguments as Map<dynamic, dynamic>)['args'] as List).cast<String>();
      final match = RegExp(r"echo '([A-Za-z0-9+/=]+)' \| base64 -d").firstMatch(cmdArgs[1]);
      expect(match, isNotNull, reason: 'the project should be staged as a tarball');

      final tarBytes = gzip.decode(base64Decode(match!.group(1)!));
      final names = TarDecoder()
          .decodeBytes(tarBytes)
          .files
          .map((f) => f.name.replaceFirst('./', ''))
          .toList();

      expect(names, contains('package.json'));
      expect(names, contains('index.js'));
      expect(names.where((n) => n.contains('node_modules')), isEmpty);
    } finally {
      await tempDir.delete(recursive: true);
    }
  });
}
