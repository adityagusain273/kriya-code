import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../workspace/fs_service.dart';

class FileTemplate {
  final String id;
  final String name;
  final String description;
  final String languageId;
  final String extension;
  final List<FileTemplateFile> files;
  final Map<String, String> variables;

  const FileTemplate({
    required this.id,
    required this.name,
    required this.description,
    required this.languageId,
    required this.extension,
    required this.files,
    this.variables = const {},
  });

  factory FileTemplate.fromJson(Map<String, dynamic> json) {
    return FileTemplate(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String,
      languageId: json['languageId'] as String,
      extension: json['extension'] as String,
      variables: Map<String, String>.from(json['variables'] ?? {}),
      files: (json['files'] as List)
          .map((f) => FileTemplateFile.fromJson(f as Map<String, dynamic>))
          .toList(),
    );
  }
}

class FileTemplateFile {
  final String relativePath;
  final String content;

  const FileTemplateFile({
    required this.relativePath,
    required this.content,
  });

  factory FileTemplateFile.fromJson(Map<String, dynamic> json) {
    return FileTemplateFile(
      relativePath: json['relativePath'] as String,
      content: json['content'] as String,
    );
  }
}

class TemplateService {
  static final Map<String, FileTemplate> _templates = {};
  static bool _loaded = false;

  static Future<void> loadAssets() async {
    if (_loaded) return;
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      for (final key in manifest.listAssets()) {
        if (key.startsWith('assets/templates/') && key.endsWith('.json')) {
          try {
            final content = await rootBundle.loadString(key);
            final Map<String, dynamic> json = jsonDecode(content);
            final template = FileTemplate.fromJson(json);
            _templates[template.id] = template;
          } catch (e) {
            // Ignore individual template load errors
          }
        }
      }
    } catch (_) {}
    _loaded = true;
  }

  static List<FileTemplate> getAllTemplates() {
    if (!_loaded) {
      // Return empty list if not loaded yet, caller should await loadAssets()
      return [];
    }
    return _templates.values.toList();
  }

  static FileTemplate? getTemplateById(String id) {
    if (!_loaded) return null;
    return _templates[id];
  }

  static List<FileTemplate> getTemplatesForLanguage(String languageId) {
    if (!_loaded) return [];
    return _templates.values.where((t) => t.languageId == languageId).toList();
  }

  static String applyVariables(String content, Map<String, String> variables) {
    String result = content;
    for (final entry in variables.entries) {
      result = result.replaceAll('{{${entry.key}}}', entry.value);
    }
    // Handle built-in variables
    result = result.replaceAll('{{date}}', _currentDate());
    return result;
  }

  static String _currentDate() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  static Future<void> createFromTemplate(
    FileTemplate template,
    String targetDir,
    Map<String, String> variables,
    FsService fs,
  ) async {
    final vars = Map<String, String>.from(template.variables);
    vars.addAll(variables);
    vars['date'] = _currentDate();
    
    for (final file in template.files) {
      final fullPath = p.join(targetDir, file.relativePath);
      final dir = p.dirname(fullPath);
      if (!fs.exists(dir)) {
        await fs.createDirectory(dir);
      }
      final content = applyVariables(file.content, vars);
      await fs.writeFile(fullPath, content);
    }
  }
}