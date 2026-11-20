import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

enum WorkloadTier {
  /// A script or a small static page. Runs on-device with no complaint.
  local,

  /// A framework project or an install step. Better served from a cloud runner.
  cloud,
}

class WorkloadAssessment {
  final WorkloadTier tier;
  final List<String> reasons;

  const WorkloadAssessment({required this.tier, required this.reasons});

  bool get prefersCloud => tier == WorkloadTier.cloud;

  /// What the console shows. One line, because the console is where a run that
  /// just died is being read.
  String get notice =>
      'Cloud Tier recommended: this project looks heavy (${reasons.join(', ')}). '
      'A dev server or build here competes with the editor for memory, and '
      'Android will kill it under load. Deploy it instead — GitHub Actions, '
      'Vercel or Netlify — and keep Kriya for editing. '
      'Single-file scripts are unaffected.';
}

/// Decides whether a run is cheap enough to do on-device.
///
/// Android's low-memory killer does not care that a framework dev server is
/// "just" a Node process: a Next.js or Vite project holds hundreds of
/// megabytes of module graph, and the editor is in the same process budget.
/// The advice is deliberately cheap — a directory listing and one small JSON
/// file, never a walk of the tree.
class WorkloadPreflight {
  const WorkloadPreflight._();

  /// Frameworks whose dev server or build step is too heavy for a phone.
  static const Set<String> heavyDependencies = {
    'next',
    'nuxt',
    'vite',
    'webpack',
    'react-scripts',
    'gatsby',
    'astro',
    '@angular/core',
    'expo',
  };

  /// Fragments that mark a script as a build or an install rather than a
  /// start-a-light-server.
  static const List<String> heavyScriptFragments = [
    'next build',
    'vite build',
    'webpack',
    'tsc',
    'turbo',
    'nx build',
    'ng build',
    'install',
  ];

  static WorkloadAssessment assess({
    Map<String, dynamic>? packageJson,
    Set<String> entryNames = const {},
    String? command,
  }) {
    final reasons = <String>[];

    final deps = <String>{};
    for (final key in const ['dependencies', 'devDependencies']) {
      final value = packageJson?[key];
      if (value is Map) deps.addAll(value.keys.cast<String>());
    }
    for (final heavy in heavyDependencies) {
      if (deps.contains(heavy)) reasons.add(heavy);
    }

    final scripts = packageJson?['scripts'];
    if (scripts is Map) {
      for (final entry in scripts.entries) {
        final line = '${entry.value}'.toLowerCase();
        for (final fragment in heavyScriptFragments) {
          if (line.contains(fragment)) {
            reasons.add('script "${entry.key}"');
            break;
          }
        }
      }
    }

    final commandLower = command?.toLowerCase();
    if (commandLower != null) {
      for (final fragment in const [
        'npm install',
        'npm ci',
        'yarn install',
        'pip install',
        'cargo build',
      ]) {
        if (commandLower.contains(fragment)) {
          reasons.add('command "$fragment"');
          break;
        }
      }
    }

    if (entryNames.contains('node_modules')) reasons.add('node_modules');

    if (reasons.isEmpty) {
      return const WorkloadAssessment(tier: WorkloadTier.local, reasons: []);
    }
    return WorkloadAssessment(tier: WorkloadTier.cloud, reasons: reasons);
  }

  /// [command] is the argv about to run, before placeholder substitution.
  static WorkloadAssessment fromDirectory(
    Directory dir, {
    String? command,
  }) {
    final pkg = File(p.join(dir.path, 'package.json'));
    Map<String, dynamic>? parsed;
    if (pkg.existsSync()) {
      try {
        final decoded = jsonDecode(pkg.readAsStringSync());
        if (decoded is Map<String, dynamic>) parsed = decoded;
      } catch (_) {
        // A malformed package.json says nothing about workload.
      }
    }

    return assess(
      packageJson: parsed,
      entryNames: entryNamesOf(dir),
      command: command,
    );
  }

  /// Top-level names only: enough to spot `node_modules` without walking it.
  static Set<String> entryNamesOf(Directory dir) {
    try {
      return dir
          .listSync(followLinks: false)
          .map((e) => p.basename(e.path))
          .toSet();
    } catch (_) {
      return const {};
    }
  }
}