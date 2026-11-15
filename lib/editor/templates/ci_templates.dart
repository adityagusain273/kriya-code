import 'package:path/path.dart' as p;

import '../../workspace/fs_service.dart';

/// One-tap CI scaffolding for projects that want their APK built on GitHub's
/// runners instead of on the phone.
class CiTemplates {
  static const buildWorkflowPath = '.github/workflows/build-apk.yml';

  /// Builds a debug or release APK and uploads it as the `app-apk` artifact,
  /// which is the name `ArtifactInstaller` looks for after a run.
  static const buildApkWorkflow = '''
name: Android APK

on:
  workflow_dispatch:
    inputs:
      build_type:
        description: 'APK type'
        required: true
        default: 'debug'
        type: choice
        options:
          - debug
          - release

jobs:
  build:
    name: Build APK
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Java 17
        uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '17'

      - name: Flutter
        uses: subosito/flutter-action@v2
        with:
          channel: stable
          cache: true

      - name: pub get
        run: flutter pub get

      - name: Build
        run: flutter build apk "--\${BUILD_TYPE}"
        env:
          BUILD_TYPE: \${{ inputs.build_type }}

      - name: Upload APK
        uses: actions/upload-artifact@v4
        with:
          name: app-apk
          path: build/app/outputs/flutter-apk/*.apk
          retention-days: 14
''';

  /// Writes [buildApkWorkflow] into [repoDir] when it is not already there.
  ///
  /// Returns false when the file already existed, so the UI can say "already
  /// configured" instead of pretending it created something.
  static Future<bool> ensureBuildWorkflow(FsService fs, String repoDir) async {
    final target = p.join(repoDir, buildWorkflowPath);
    if (fs.exists(target)) return false;
    final workflowsDir = p.dirname(target);
    if (!fs.exists(workflowsDir)) {
      await fs.createDirectory(workflowsDir);
    }
    await fs.writeFile(target, buildApkWorkflow);
    return true;
  }
}
