import 'dart:convert';
import 'dart:io';

import 'package:kriya_code/editor/templates/template_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  FileTemplate load(String name) => FileTemplate.fromJson(
        jsonDecode(File('assets/templates/$name.json').readAsStringSync())
            as Map<String, dynamic>,
      );

  for (final name in ['fullstack_react_supabase', 'fullstack_node_api']) {
    test('$name declares every placeholder it uses', () {
      final template = load(name);
      final known = {...template.variables.keys, 'date', 'author'};
      final used = <String>{};
      for (final file in template.files) {
        for (final match in RegExp(r'\{\{([A-Za-z_]+)\}\}').allMatches(file.content)) {
          used.add(match.group(1)!);
        }
      }
      expect(used.difference(known), isEmpty,
          reason: 'a placeholder without a value renders as literal {{...}}');
      expect(template.variables.keys.toSet().difference(used), isEmpty,
          reason: 'a variable the user is asked to fill is never rendered');
    });

    test('$name package.json is valid after substitution', () {
      final template = load(name);
      final pkg = template.files.firstWhere((f) => f.relativePath == 'package.json');
      final content = TemplateService.applyVariables(pkg.content, template.variables);
      final decoded = jsonDecode(content) as Map<String, dynamic>;

      expect(decoded['name'], template.variables['projectName']);
      expect(decoded['dependencies'], isNotEmpty);
      expect(decoded['scripts'], isNotEmpty);
    });
  }

  test('react template boots Supabase auth and documents the env example', () {
    final template = load('fullstack_react_supabase');
    final paths = template.files.map((f) => f.relativePath).toList();

    expect(paths, contains('src/lib/supabaseClient.ts'));
    expect(paths, contains('src/lib/auth.ts'));
    expect(paths, contains('.env.example'));

    final client = template.files
        .firstWhere((f) => f.relativePath == 'src/lib/supabaseClient.ts')
        .content;
    expect(client, contains("from '@supabase/supabase-js'"));
    expect(client, contains('createClient'));
    expect(client, contains('persistSession'));

    final env = template.files.firstWhere((f) => f.relativePath == '.env.example').content;
    expect(env, contains('VITE_SUPABASE_URL='));
    expect(env, contains('VITE_SUPABASE_ANON_KEY='));
  });

  test('node template has a pool, CORS and a schema', () {
    final template = load('fullstack_node_api');
    final paths = template.files.map((f) => f.relativePath).toList();

    expect(paths, contains('src/db.js'));
    expect(paths, contains('sql/schema.sql'));

    final db = template.files.firstWhere((f) => f.relativePath == 'src/db.js').content;
    expect(db, contains('new Pool'));
    expect(db, contains('DATABASE_URL'));

    final index = template.files.firstWhere((f) => f.relativePath == 'src/index.js').content;
    expect(index, contains('cors('));
    expect(index, contains('/api/health'));
    expect(index, contains("'0.0.0.0'"));
  });
}
