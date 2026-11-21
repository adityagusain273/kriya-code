import 'dart:io';

import 'package:kriya_code/editor/templates/ci_templates.dart';
import 'package:kriya_code/workspace/fs_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;
  late FsService fs;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('bcode_ci_template');
    fs = FsService(temp.path);
  });

  tearDown(() => temp.deleteSync(recursive: true));

  test('scaffolds the workflow once and never overwrites it', () async {
    final file = File(p.join(temp.path, CiTemplates.buildWorkflowPath));
    expect(file.existsSync(), isFalse);

    expect(await CiTemplates.ensureBuildWorkflow(fs, temp.path), isTrue);
    expect(file.existsSync(), isTrue);
    expect(file.readAsStringSync(), CiTemplates.buildApkWorkflow);
    expect(file.readAsStringSync(), contains('workflow_dispatch'));
    expect(file.readAsStringSync(), contains('name: app-apk'));

    file.writeAsStringSync('name: my own workflow\n');
    expect(await CiTemplates.ensureBuildWorkflow(fs, temp.path), isFalse);
    expect(file.readAsStringSync(), 'name: my own workflow\n');
  });

  test('the template is a valid dispatchable GitHub Actions file', () {
    final yaml = CiTemplates.buildApkWorkflow;
    expect(yaml, startsWith('name:'));
    expect(yaml, contains('on:\n  workflow_dispatch:'));
    expect(yaml, contains('runs-on: ubuntu-latest'));
    expect(yaml, contains('flutter build apk'));
    expect(yaml, contains('actions/upload-artifact@v4'));
  });
}
