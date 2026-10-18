import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/di.dart';
import '../workspace/fs_service.dart';
import 'tab_manager.dart';

class QuickOpenEntry {
  final String path;
  final String name;
  final bool isRecent;

  const QuickOpenEntry({
    required this.path,
    required this.name,
    this.isRecent = false,
  });

  String get displayName => name;
}

class QuickOpen extends StatefulWidget {
  const QuickOpen({super.key});

  static Future<void> show(BuildContext context) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const QuickOpen(),
    );
  }

  @override
  State<QuickOpen> createState() => _QuickOpenState();
}

class _QuickOpenState extends State<QuickOpen> {
  final _searchCtrl = TextEditingController();
  final _focusNode = FocusNode();
  List<QuickOpenEntry> _allEntries = [];
  List<QuickOpenEntry> _filtered = [];
  int _selectedIndex = 0;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _loadEntries();
    _searchCtrl.addListener(_filter);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  Future<void> _loadEntries() async {
    final fs = sl<FsService>();
    final tabs = sl<TabManager>();
    
    final recentPaths = tabs.tabs.map((t) => t.filePath).toList();
    final recentSet = recentPaths.toSet();
    
    final allFiles = await _collectFiles(fs, '.');
    
    final entries = <QuickOpenEntry>[];
    
    // Add recent files first
    for (final path in recentPaths) {
      entries.add(QuickOpenEntry(
        path: path,
        name: path.split('/').last,
        isRecent: true,
      ));
    }
    
    // Add all other files
    for (final file in allFiles) {
      if (!recentSet.contains(file)) {
        entries.add(QuickOpenEntry(
          path: file,
          name: file.split('/').last,
          isRecent: false,
        ));
      }
    }
    
    if (mounted) {
      setState(() {
        _allEntries = entries;
        _filtered = entries;
        _initialized = true;
      });
    }
  }

  Future<List<String>> _collectFiles(FsService fs, String dir) async {
    final result = <String>[];
    try {
      final entries = await fs.list(dir);
      for (final entry in entries) {
        if (entry.isDirectory) {
          result.addAll(await _collectFiles(fs, entry.path));
        } else {
          result.add(entry.path);
        }
      }
    } catch (_) {}
    return result;
  }

  void _filter() {
    final query = _searchCtrl.text.toLowerCase();
    setState(() {
      _selectedIndex = 0;
      if (query.isEmpty) {
        _filtered = _allEntries;
      } else {
        _filtered = _allEntries.where((e) {
          final name = e.name.toLowerCase();
          final path = e.path.toLowerCase();
          return name.contains(query) || path.contains(query) || _fuzzyMatch(query, name);
        }).toList();
      }
    });
  }

  bool _fuzzyMatch(String query, String target) {
    int queryIdx = 0;
    for (int i = 0; i < target.length && queryIdx < query.length; i++) {
      if (target[i] == query[queryIdx]) {
        queryIdx++;
      }
    }
    return queryIdx == query.length;
  }

  void _execute(int index) {
    if (index < 0 || index >= _filtered.length) return;
    final entry = _filtered[index];
    Navigator.pop(context);
    sl<TabManager>().open(entry.path);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final height = MediaQuery.of(context).size.height * 0.6;

    return Container(
      height: height,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(Icons.search, size: 20, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    focusNode: _focusNode,
                    decoration: InputDecoration(
                      hintText: 'Type to search files...',
                      isDense: true,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                    style: const TextStyle(fontSize: 16),
                    onSubmitted: (_) => _execute(_selectedIndex),
                  ),
                ),
                if (_searchCtrl.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () {
                      _searchCtrl.clear();
                      _filter();
                    },
                  ),
              ],
            ),
          ),
          if (!_initialized)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else
            Expanded(
              child: KeyboardListener(
                focusNode: FocusNode(),
                onKeyEvent: (event) {
                  if (event is! KeyDownEvent) return;
                  if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                    setState(() {
                      _selectedIndex = (_selectedIndex + 1).clamp(0, _filtered.length - 1);
                    });
                  } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                    setState(() {
                      _selectedIndex = (_selectedIndex - 1).clamp(0, _filtered.length - 1);
                    });
                  } else if (event.logicalKey == LogicalKeyboardKey.enter) {
                    _execute(_selectedIndex);
                  } else if (event.logicalKey == LogicalKeyboardKey.escape) {
                    Navigator.pop(context);
                  }
                },
                child: _filtered.isEmpty
                    ? Center(
                        child: Text(
                          _searchCtrl.text.isEmpty ? 'No files found' : 'No matches',
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _filtered.length,
                        padding: const EdgeInsets.only(bottom: 8),
                        itemBuilder: (ctx, i) {
                          final entry = _filtered[i];
                          final selected = i == _selectedIndex;
                          return ListTile(
                            dense: true,
                            selected: selected,
                            selectedTileColor: cs.primaryContainer.withValues(alpha: 0.3),
                            leading: Icon(
                              entry.isRecent ? Icons.history : Icons.insert_drive_file,
                              size: 18,
                              color: entry.isRecent ? cs.primary : cs.onSurfaceVariant,
                            ),
                            title: Text(
                              entry.name,
                              style: const TextStyle(fontSize: 13),
                            ),
                            subtitle: Text(
                              entry.path,
                              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: entry.isRecent
                                ? Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: cs.primaryContainer,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      'Recent',
                                      style: TextStyle(
                                        fontSize: 9,
                                        color: cs.onPrimaryContainer,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  )
                                : null,
                            onTap: () => _execute(i),
                          );
                        },
                      ),
              ),
            ),
        ],
      ),
    );
  }
}