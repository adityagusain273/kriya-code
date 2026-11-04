import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../core/di.dart';
import '../workspace/fs_service.dart';
import 'tab_manager.dart';

class SearchResult {
  final String filePath;
  final int lineNumber;
  final String lineContent;
  final int matchStart;
  final int matchEnd;

  const SearchResult({
    required this.filePath,
    required this.lineNumber,
    required this.lineContent,
    required this.matchStart,
    required this.matchEnd,
  });
}

class GlobalSearchPage extends StatefulWidget {
  const GlobalSearchPage({super.key});

  static Future<void> show(BuildContext context) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const GlobalSearchPage()),
    );
  }

  @override
  State<GlobalSearchPage> createState() => _GlobalSearchPageState();
}

class _GlobalSearchPageState extends State<GlobalSearchPage> {
  final _queryCtrl = TextEditingController();
  final _focusNode = FocusNode();
  List<SearchResult> _results = [];
  bool _searching = false;
  bool _caseSensitive = false;
  bool _regexMode = false;
  String? _error;

  static const _ignoreDirs = {
    '.git', '.dart_tool', 'build', '.idea', '.vscode', '__pycache__',
    'node_modules', '.gradle', '.pub-cache',
  };

  @override
  void initState() {
    super.initState();
    _focusNode.requestFocus();
  }

  int _searchGen = 0;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _queryCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onQueryChanged(String v) {
    _debounce?.cancel();
    setState(() => _results = []);
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(v));
  }

  Future<void> _search(String query) async {
    final gen = ++_searchGen;
    if (query.isEmpty) {
      setState(() => _results = []);
      return;
    }
    setState(() {
      _searching = true;
      _error = null;
      _results = [];
    });

    try {
      final fs = sl<FsService>();
      final root = fs.rootPath;
      final results = <SearchResult>[];
      RegExp? regex;

      if (_regexMode) {
        try {
          regex = RegExp(query, caseSensitive: _caseSensitive);
        } catch (e) {
          setState(() {
            _error = 'Invalid regex: $e';
            _searching = false;
          });
          return;
        }
      }

      await _searchDir(Directory(root), root, query, results, regex, gen);
      if (mounted && gen == _searchGen) {
        setState(() {
          _results = results;
          _searching = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Search error: $e';
          _searching = false;
        });
      }
    }
  }

  Future<void> _searchDir(
    Directory dir,
    String root,
    String query,
    List<SearchResult> results,
    RegExp? regex,
    int gen, {
    int depth = 0,
  }) async {
    if (gen != _searchGen) return;
    if (depth > 12) return;
    if (!await dir.exists()) return;

    await for (final entity in dir.list(followLinks: false)) {
      if (gen != _searchGen) return;
      if (results.length > 500) return;
      if (entity is Directory) {
        final name = p.basename(entity.path);
        if (_ignoreDirs.contains(name) || name.startsWith('.')) continue;
        await _searchDir(entity, root, query, results, regex, gen, depth: depth + 1);
      } else if (entity is File) {
        final name = p.basename(entity.path);
        if (name.startsWith('.')) continue;
        final ext = p.extension(name).toLowerCase();
        if (_isBinaryExtension(ext)) continue;
        await _searchFile(entity, root, query, results, regex);
      }
    }
  }

  bool _isBinaryExtension(String ext) {
    const bins = {
      '.png', '.jpg', '.jpeg', '.gif', '.bmp', '.ico', '.svg',
      '.mp3', '.mp4', '.wav', '.avi', '.mov',
      '.zip', '.tar', '.gz', '.7z', '.rar',
      '.exe', '.dll', '.so', '.dylib',
      '.pdf', '.doc', '.docx', '.xls', '.xlsx',
      '.class', '.o', '.obj',
    };
    return bins.contains(ext);
  }

  Future<void> _searchFile(
    File file,
    String root,
    String query,
    List<SearchResult> results,
    RegExp? regex,
  ) async {
    try {
      // Do not index a file this app cannot open in the editor either. Reading
      // unbounded content froze the UI isolate and can OOM on a multi-hundred-MB
      // file.
      if (await file.length() > 2 * 1024 * 1024) return;
      final content = await file.readAsString();
      final lines = content.split('\n');
      final relativePath = p.relative(file.path, from: root);

      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (regex != null) {
          final match = regex.firstMatch(line);
          if (match != null) {
            results.add(SearchResult(
              filePath: relativePath,
              lineNumber: i + 1,
              lineContent: line.trim(),
              matchStart: match.start,
              matchEnd: match.end,
            ));
          }
        } else {
          final h = _caseSensitive ? line : line.toLowerCase();
          final n = _caseSensitive ? query : query.toLowerCase();
          final idx = h.indexOf(n);
          if (idx >= 0) {
            results.add(SearchResult(
              filePath: relativePath,
              lineNumber: i + 1,
              lineContent: line.trim(),
              matchStart: idx,
              matchEnd: idx + query.length,
            ));
          }
        }
      }
    } catch (_) {}
  }

  /// Opens the matched file and puts the cursor on the match.
  ///
  /// Opening the file alone was the bug this replaces: with a long file the user
  /// still had to find the line they had just searched for.
  Future<void> _openResult(SearchResult result) async {
    final fs = sl<FsService>();
    final fullPath = p.join(fs.rootPath, result.filePath);
    final tabs = sl<TabManager>();
    try {
      final tab = await tabs.open(fullPath);
      final offset = await _offsetOf(result);
      if (offset != null) tab.revealAt(offset);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e is StateError ? e.message : 'Could not open ${result.filePath}: $e'),
      ));
    }
  }

  /// Character offset of the match, counted across the file's lines.
  Future<int?> _offsetOf(SearchResult result) async {
    final fs = sl<FsService>();
    final file = File(p.join(fs.rootPath, result.filePath));
    if (!await file.exists()) return null;
    final lines = await file.readAsLines();
    final index = result.lineNumber - 1;
    if (index < 0 || index >= lines.length) return null;
    var offset = 0;
    for (var i = 0; i < index; i++) {
      offset += lines[i].length + 1;
    }
    final column = result.matchStart.clamp(0, lines[index].length);
    return offset + column;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Global Search', style: TextStyle(fontSize: 16)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                TextField(
                  controller: _queryCtrl,
                  focusNode: _focusNode,
                  decoration: InputDecoration(
                    hintText: 'Search in all files...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    isDense: true,
                    border: const OutlineInputBorder(),
                    suffixText: _results.isNotEmpty ? '${_results.length} results' : null,
                  ),
                  style: const TextStyle(fontSize: 14),
                  onChanged: _onQueryChanged,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    FilterChip(
                      label: const Text('Aa', style: TextStyle(fontSize: 12)),
                      selected: _caseSensitive,
                      onSelected: (v) {
                        setState(() => _caseSensitive = v);
                        _searchGen++;
                        _search(_queryCtrl.text);
                      },
                      visualDensity: VisualDensity.compact,
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: const Text('.*', style: TextStyle(fontSize: 12)),
                      selected: _regexMode,
                      onSelected: (v) {
                        setState(() => _regexMode = v);
                        _searchGen++;
                        _search(_queryCtrl.text);
                      },
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (_searching)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            Expanded(
              child: Center(
                child: Text(_error!, style: TextStyle(color: cs.error)),
              ),
            )
          else if (_results.isEmpty && _queryCtrl.text.isNotEmpty)
            const Expanded(child: Center(child: Text('No results found')))
          else
            Expanded(
              child: ListView.builder(
                itemCount: _results.length,
                itemBuilder: (ctx, i) {
                  final r = _results[i];
                  final fileName = p.basename(r.filePath);
                  return ListTile(
                    dense: true,
                    leading: Icon(Icons.description, size: 16, color: cs.primary),
                    title: Text.rich(
                      TextSpan(children: [
                        TextSpan(
                          text: '$fileName:',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: cs.primary,
                          ),
                        ),
                        TextSpan(
                          text: '${r.lineNumber}',
                          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                        ),
                        const TextSpan(text: ' '),
                        TextSpan(
                          text: r.lineContent,
                          style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                        ),
                      ]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(r.filePath, style: const TextStyle(fontSize: 10)),
                    onTap: () => _openResult(r),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
