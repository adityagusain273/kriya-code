import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String readRepoFile(String path) {
  final file = File(path);
  expect(
    file.existsSync(),
    isTrue,
    reason: '$path is missing, so the hardening invariants cannot be checked',
  );
  return file.readAsStringSync();
}

void main() {
  group('release manifest', () {
    test('forbids cleartext traffic and backups', () {
      final manifest = readRepoFile('android/app/src/main/AndroidManifest.xml');

      expect(manifest, contains('android:usesCleartextTraffic="false"'));
      expect(manifest, contains('android:allowBackup="false"'));
      expect(manifest, contains('android:fullBackupContent="false"'));
    });

    test('is never debuggable', () {
      for (final path in <String>[
        'android/app/src/main/AndroidManifest.xml',
        'android/app/src/debug/AndroidManifest.xml',
        'android/app/src/profile/AndroidManifest.xml',
      ]) {
        final manifest = readRepoFile(path);
        expect(
          manifest,
          isNot(contains('android:debuggable="true"')),
          reason: '$path must not mark the app debuggable',
        );
      }
    });

    test('does not request a large heap', () {
      final manifest = readRepoFile('android/app/src/main/AndroidManifest.xml');
      expect(manifest, isNot(contains('android:largeHeap')));
    });

    test('exports only the launcher activity', () {
      final manifest = readRepoFile('android/app/src/main/AndroidManifest.xml');
      final exported = RegExp(
        r'android:exported="true"',
      ).allMatches(manifest).length;
      expect(exported, 1);
      expect(manifest, contains('android:name=".MainActivity"'));
    });
  });

  group('release build', () {
    test('shrinks and obfuscates', () {
      final gradle = readRepoFile('android/app/build.gradle.kts');

      expect(gradle, contains('isMinifyEnabled = true'));
      expect(gradle, contains('isShrinkResources = true'));
      expect(gradle, contains('"dart-obfuscation", "true"'));
      expect(gradle, contains('"split-debug-info"'));
    });

    test('keeps the native symbol table for the Play bundle', () {
      final gradle = readRepoFile('android/app/build.gradle.kts');

      // Flutter's appbundle check requires libflutter/libapp symbol files in
      // the AAB; "NONE" made every signed release fail after a good build.
      // The APK never ships these files.
      expect(gradle, contains('debugSymbolLevel = "SYMBOL_TABLE"'));
      expect(gradle, isNot(contains('debugSymbolLevel = "NONE"')));
    });

    test('refuses to build a release APK without a release key', () {
      final gradle = readRepoFile('android/app/build.gradle.kts');

      expect(
        gradle,
        contains('Refusing to build a release APK without a usable release signing key.'),
      );
    });
  });

  group('proguard rules', () {
    test('keeps the libraries that resolve classes or JNI by name', () {
      final rules = readRepoFile('android/app/proguard-rules.pro');

      for (final rule in <String>[
        'com.it_nomads.fluttersecurestorage',
        'com.engincode.flutter_secure_app',
        'dev.fluttercommunity.plus.packageinfo',
        'dev.fluttercommunity.plus.device_info',
        'org.apache.commons.compress',
        'org.tukaani.xz',
        'com.github.luben.zstd',
      ]) {
        expect(rules, contains(rule), reason: '$rule must be kept');
      }
      expect(rules, contains('native <methods>;'));
    });

    test('keeps the app classes the Flutter engine reaches', () {
      final rules = readRepoFile('android/app/proguard-rules.pro');
      expect(rules, contains('com.bcode.editor.'));
    });
  });

  group('continuous integration', () {
    test('never signs a release build with the debug key', () {
      final workflow = readRepoFile('.github/workflows/build-apk.yml');

      for (final line in workflow.split('\n')) {
        final isReleaseBuild = line.contains('--release');
        final usesSideload = line.contains('bcode.sideload');
        expect(
          isReleaseBuild && usesSideload,
          isFalse,
          reason: 'a release build must not set bcode.sideload: $line',
        );
      }
    });

    test('uploads the symbol file instead of shipping it', () {
      final workflow = readRepoFile('.github/workflows/build-apk.yml');
      expect(workflow, contains('symbols'));
    });
  });

  group('secrets', () {
    test('no OAuth client secret is compiled into the Dart tree', () {
      final clientSecret = RegExp(
        r'''client_secret['"]?\s*[:=]\s*['"][A-Za-z0-9_\-]{8,}''',
      );
      final token = RegExp(r'''gh[pousr]_[A-Za-z0-9]{20,}''');

      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final source = entity.readAsStringSync();
        expect(
          clientSecret.hasMatch(source),
          isFalse,
          reason: '${entity.path} embeds a client secret',
        );
        expect(
          token.hasMatch(source),
          isFalse,
          reason: '${entity.path} embeds a token',
        );
      }
    });

    test('the ignore rules keep signing material out of the repository', () {
      final ignore = readRepoFile('.gitignore');

      expect(ignore, contains('key.properties'));
      expect(ignore, contains('*.jks'));
      expect(ignore, contains('*.keystore'));
    });
  });
}
