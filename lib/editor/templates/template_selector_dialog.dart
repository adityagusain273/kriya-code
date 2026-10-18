import 'package:flutter/material.dart';

import 'template_service.dart';
import '../../workspace/fs_service.dart';

class TemplateSelectorDialog extends StatefulWidget {
  final String targetDir;
  final FsService fs;
  final VoidCallback? onCreated;

  const TemplateSelectorDialog({
    super.key,
    required this.targetDir,
    required this.fs,
    this.onCreated,
  });

  static Future<void> show(
    BuildContext context, {
    required String targetDir,
    required FsService fs,
    VoidCallback? onCreated,
  }) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => TemplateSelectorDialog(
        targetDir: targetDir,
        fs: fs,
        onCreated: onCreated,
      ),
    );
  }

  @override
  State<TemplateSelectorDialog> createState() => _TemplateSelectorDialogState();
}

class _TemplateSelectorDialogState extends State<TemplateSelectorDialog> {
  final _searchCtrl = TextEditingController();
  List<FileTemplate> _filtered = [];
  FileTemplate? _selected;
  int _step = 0; // 0 = select template, 1 = configure variables
  final Map<String, TextEditingController> _varControllers = {};
  bool _creating = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_filter);
    _loadTemplates();
  }

  Future<void> _loadTemplates() async {
    await TemplateService.loadAssets();
    if (mounted) {
      setState(() {
        _filtered = TemplateService.getAllTemplates();
        _loaded = true;
      });
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    for (final c in _varControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _filter() {
    final query = _searchCtrl.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filtered = TemplateService.getAllTemplates();
      } else {
        _filtered = TemplateService.getAllTemplates().where((t) {
          return t.name.toLowerCase().contains(query) ||
              t.description.toLowerCase().contains(query) ||
              t.id.toLowerCase().contains(query);
        }).toList();
      }
    });
  }

  void _selectTemplate(FileTemplate template) {
    setState(() {
      _selected = template;
      _step = 1;
      _varControllers.clear();
      for (final key in template.variables.keys) {
        _varControllers[key] = TextEditingController(text: template.variables[key] ?? '');
      }
    });
  }

  void _goBack() {
    setState(() {
      _step = 0;
      _selected = null;
      for (final c in _varControllers.values) {
        c.dispose();
      }
      _varControllers.clear();
    });
  }

  Future<void> _create() async {
    if (_selected == null) return;

    setState(() => _creating = true);

    try {
      final variables = <String, String>{};
      for (final entry in _varControllers.entries) {
        variables[entry.key] = entry.value.text.trim();
      }

      await TemplateService.createFromTemplate(
        _selected!,
        widget.targetDir,
        variables,
        widget.fs,
      );

      if (mounted) {
        Navigator.pop(context);
        widget.onCreated?.call();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Created from "${_selected!.name}" template')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (_step == 1)
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: _goBack,
                ),
              Expanded(
                child: Text(
                  _step == 0 ? 'New from Template' : 'Configure: ${_selected?.name}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              if (_step == 0)
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
            ],
          ),
          if (_step == 0) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _searchCtrl,
              decoration: const InputDecoration(
                hintText: 'Search templates...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: !_loaded
                  ? const Center(child: CircularProgressIndicator())
                  : _filtered.isEmpty
                      ? Center(
                          child: Text(
                            _searchCtrl.text.isEmpty
                                ? 'No templates available.'
                                : 'No templates found for "${_searchCtrl.text}"',
                            style: const TextStyle(color: Colors.white54),
                          ),
                        )
                      : ListView.separated(
                          itemCount: _filtered.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (ctx, i) {
                            final template = _filtered[i];
                            return ListTile(
                              leading: Icon(_iconForLanguage(template.languageId), color: cs.primary),
                              title: Text(template.name),
                              subtitle: Text(template.description),
                              onTap: () => _selectTemplate(template),
                            );
                          },
                        ),
            ),
          ] else if (_step == 1) ...[
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                children: [
                  Text(
                    'Template Variables',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  ..._selected!.variables.keys.map((key) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: TextField(
                        controller: _varControllers[key],
                        decoration: InputDecoration(
                          labelText: key,
                          hintText: _selected!.variables[key],
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 16),
                  Text(
                    'Files to be created:',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  ..._selected!.files.map((f) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Icon(Icons.insert_drive_file, size: 18, color: cs.onSurfaceVariant),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            f.relativePath,
                            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  )),
                ],
              ),
            ),
            FilledButton(
              onPressed: _creating ? null : _create,
              child: _creating
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Create'),
            ),
          ],
        ],
      ),
    );
  }

  IconData _iconForLanguage(String languageId) {
    switch (languageId) {
      case 'dart': return Icons.flutter_dash;
      case 'typescript':
      case 'javascript': return Icons.web;
      case 'html': return Icons.code;
      case 'python': return Icons.terminal;
      case 'java': return Icons.coffee;
      case 'cpp': return Icons.memory;
      default: return Icons.description;
    }
  }
}