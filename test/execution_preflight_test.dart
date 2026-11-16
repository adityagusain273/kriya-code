import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:b_code/execution/storage_preflight.dart';
import 'package:b_code/execution/workload_preflight.dart';

void main() {
  group('StoragePreflight', () {
    test('refuses when free space is below twice the download', () {
      const mb = 1024 * 1024;
      final check = StoragePreflight.evaluate(packedBytes: 500 * mb, freeBytes: 999 * mb);

      expect(check.verdict, StorageVerdict.insufficient);
      expect(check.allowsInstall, isFalse);
      expect(check.requiredBytes, 1000 * mb);
      expect(check.message, contains('Not enough free space'));
      expect(check.message, contains('500 MB'));
    });

    test('allows exactly twice the download', () {
      final check = StoragePreflight.evaluate(packedBytes: 500, freeBytes: 1000);

      expect(check.verdict, StorageVerdict.fits);
      expect(check.allowsInstall, isTrue);
    });

    test('an unreadable volume is unknown, not a refusal', () {
      final check = StoragePreflight.evaluate(packedBytes: 500, freeBytes: null);

      expect(check.verdict, StorageVerdict.unknown);
      expect(check.allowsInstall, isTrue);
    });

    test('unpacking needs one copy, not two', () {
      // The .debs are already on disk by this point.
      final tight = StoragePreflight.evaluateExtraction(
        packedBytes: 500,
        freeBytes: 700,
      );
      final fine = StoragePreflight.evaluateExtraction(
        packedBytes: 500,
        freeBytes: 500,
      );

      expect(tight.verdict, StorageVerdict.fits);
      expect(fine.verdict, StorageVerdict.fits);
      expect(
        StoragePreflight.evaluateExtraction(packedBytes: 500, freeBytes: 499)
            .verdict,
        StorageVerdict.insufficient,
      );
    });

    test('formats bytes for a message', () {
      expect(DeviceStorage.formatBytes(1024 * 1024), '1 MB');
      expect(DeviceStorage.formatBytes(1536 * 1024), '2 MB');
      expect(DeviceStorage.formatBytes(3 * 1024 * 1024 * 1024), '3.0 GB');
    });
  });

  group('WorkloadPreflight', () {
    test('a single-file script stays local', () {
      final assessment = WorkloadPreflight.assess();

      expect(assessment.tier, WorkloadTier.local);
      expect(assessment.prefersCloud, isFalse);
      expect(assessment.reasons, isEmpty);
    });

    test('a framework dependency means cloud tier', () {
      for (final heavy in ['next', 'vite', 'webpack', '@angular/core']) {
        final assessment = WorkloadPreflight.assess(
          packageJson: {
            'dependencies': {heavy: '^1.0.0'},
          },
        );

        expect(assessment.prefersCloud, isTrue, reason: heavy);
        expect(assessment.reasons, contains(heavy));
      }
    });

    test('a build script means cloud tier even without the dependency', () {
      final assessment = WorkloadPreflight.assess(
        packageJson: {
          'scripts': {'build': 'next build', 'lint': 'eslint .'},
        },
      );

      expect(assessment.prefersCloud, isTrue);
      expect(assessment.reasons, contains('script "build"'));
      expect(assessment.reasons, isNot(contains('script "lint"')));
    });

    test('an install command means cloud tier', () {
      final assessment = WorkloadPreflight.assess(command: 'npm install');

      expect(assessment.prefersCloud, isTrue);
      expect(assessment.notice, contains('Cloud Tier recommended'));
    });

    test('node_modules in the project means cloud tier', () {
      final assessment = WorkloadPreflight.assess(
        entryNames: {'lib', 'node_modules'},
      );

      expect(assessment.prefersCloud, isTrue);
      expect(assessment.reasons, contains('node_modules'));
    });

    test('a malformed package.json is ignored rather than thrown', () {
      final assessment = WorkloadPreflight.assess(
        packageJson: null,
        command: 'node app.js',
      );

      expect(assessment.tier, WorkloadTier.local);
    });

    test('reads a real project directory', () async {
      final temp = Directory.systemTemp.createTempSync('bcode_workload_');
      addTearDown(() => temp.deleteSync(recursive: true));

      await File('${temp.path}/package.json').writeAsString(
        jsonEncode({
          'devDependencies': {'vite': '^5.0.0'},
          'scripts': {'dev': 'vite --host', 'lint': 'eslint .'},
        }),
      );

      final heavy = WorkloadPreflight.fromDirectory(temp);
      expect(heavy.prefersCloud, isTrue, reason: 'a vite dev script is a framework project');
      expect(heavy.reasons, contains('vite'));
      expect(heavy.reasons, isNot(contains('script "lint"')));

      await File('${temp.path}/package.json').delete();
      await File('${temp.path}/main.py').writeAsString('print(1)\n');

      expect(
        WorkloadPreflight.fromDirectory(temp).prefersCloud,
        isFalse,
        reason: 'a lone script stays local',
      );
    });
  });
}