import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'explorer_prefs.dart';
import 'file_icons.dart';
import 'fs_service.dart';
import 'import_actions.dart';
import '../../editor/templates/template_selector_dialog.dart';
import '../core/di.dart';
import '../core/archive_extractor.dart';
import '../editor/tab_manager.dart';
import '../plugins/host/extension_install_store.dart';

/// Unpacks the archive at [path] into a sibling folder, then refreshes the tree.
///
/// Shares its implementation with the "Unzip Project" flow on the empty state, which
/// is what let this one drift into offering itself on files that were never archives.
Future<bool> _extractArchive(
  String path,
  FsService fs,
  BuildContext context,
  VoidCallback onReload,
) async {
  final result = await unpackArchive(context, path);
  if (result == null) return false;
  if (context.mounted) onReload();
  return true;
}

/// Lets the page ask the explorer to expand down to a freshly imported path.
///
/// The import happens on another screen, so the folder that just arrived is otherwise
/// collapsed at the root behind a row the user has to find themselves.
class FileExplorerController extends ChangeNotifier {
  String? _pending;

  String? takePending() {
    final value = _pending;
    _pending = null;
    return value;
  }

  void reveal(String relativePath) {
    _pending = relativePath;
    notifyListeners();
  }
}

class FileExplorer extends StatefulWidget {
  final FsService fs;
  final ValueChanged<String> onFileTap;
  final VoidCallback onChanged;
  final String? activeFile;
  final ExplorerPrefs? prefs;
  final FileExplorerController? controller;

  const FileExplorer({
    super.key,
    required this.fs,
    required this.onFileTap,
    required this.onChanged,
    this.activeFile,
    this.prefs,
    this.controller,
  });

  @override
  State<FileExplorer> createState() => _FileExplorerState();
}
class _FileExplorerState extends State<FileExplorer> {
  late Future<List<FsEntry>> _rootFuture;
  late final Set<String> _expandedDirs =
      widget.prefs?.loadExpanded() ?? <String>{};
  late bool _showHidden;
  String? _selectedDir;
  int _reloadGen = 0;
  final _refreshKey = GlobalKey<RefreshIndicatorState>();

  @override
  void initState() {
    super.initState();
    _showHidden = widget.prefs?.loadShowHidden() ?? false;
    widget.fs.showHidden = _showHidden;
    _rootFuture = _loadRoot();
    widget.controller?.addListener(_onRevealRequested);
  }

  @override
  void didUpdateWidget(FileExplorer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_onRevealRequested);
      widget.controller?.addListener(_onRevealRequested);
    }
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_onRevealRequested);
    super.dispose();
  }

  void _onRevealRequested() {
    final path = widget.controller?.takePending();
    if (path == null) return;
    _expandAncestorsOf(path);
  }

  /// Opens every folder between the root and [relativePath].
  void _expandAncestorsOf(String relativePath) {
    final segments = relativePath.split('/')..removeLast();
    var acc = '';
    var changed = false;
    for (final segment in segments) {
      if (segment.isEmpty) continue;
      acc = acc.isEmpty ? segment : '$acc/$segment';
      changed |= _expandedDirs.add(acc);
    }
    if (changed) widget.prefs?.saveExpanded(_expandedDirs);
    _reload(refresh: true);
  }

  Future<List<FsEntry>> _loadRoot({bool refresh = false}) async {
    _pruneMissing();
    final selected = _selectedDir;
    if (selected != null && !widget.fs.exists(selected)) {
      _selectedDir = null;
    }
    return widget.fs.list('.', refresh: refresh);
  }

  Future<void> _reload({bool refresh = false}) async {
    final future = _loadRoot(refresh: refresh);
    setState(() {
      _reloadGen++;
      _rootFuture = future;
    });
    await future;
  }

  void _selectDir(String relativePath) {
    setState(() => _selectedDir = relativePath);
  }

  void _clearSelection() {
    setState(() => _selectedDir = null);
  }

  void _pruneMissing() {
    if (_expandedDirs.isEmpty) return;
    final removed = _expandedDirs
        .where((rel) => rel != '.' && !widget.fs.exists(rel))
        .toList();
    if (removed.isEmpty) return;
    _expandedDirs.removeAll(removed);
    widget.prefs?.saveExpanded(_expandedDirs);
  }

  void _onToggleDir(String relativePath, bool expanded) {
    if (expanded) {
      _expandedDirs.add(relativePath);
    } else {
      _expandedDirs.remove(relativePath);
    }
    widget.prefs?.saveExpanded(_expandedDirs);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        sl<ExtensionInstallStore>(),
        if (widget.controller != null) widget.controller!,
      ]),
      builder: (context, _) {
        return Scaffold(
          backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Explorer', style: TextStyle(fontSize: 14)),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: Icon(
              _showHidden
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              size: 20,
            ),
            tooltip: _showHidden ? 'Hide hidden files' : 'Show hidden files',
            onPressed: () {
              final next = !_showHidden;
              widget.fs.showHidden = next;
              widget.prefs?.saveShowHidden(next);
              setState(() => _showHidden = next);
              _reload(refresh: true);
            },
          ),
          IconButton(
            icon: const Icon(Icons.note_add_outlined, size: 20),
            tooltip: 'New file',
            onPressed: () => _createEntry(isFolder: false),
          ),
          IconButton(
            icon: const Icon(Icons.create_new_folder_outlined, size: 20),
            tooltip: 'New folder',
            onPressed: () => _createEntry(isFolder: true),
          ),
          IconButton(
            icon: const Icon(Icons.description_outlined, size: 20),
            tooltip: 'New file from a template',
            onPressed: () => _createFromTemplate(),
          ),
        ],
      ),
      body: RefreshIndicator(
        key: _refreshKey,
        onRefresh: () => _reload(refresh: true),
        child: Column(
        children: [
          if (_selectedDir != null)
            _TargetBar(target: _selectedDir!, onClear: _clearSelection),
          Expanded(
            child: FutureBuilder<List<FsEntry>>(
              future: _rootFuture,
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
                          const SizedBox(height: 12),
                          Text(
                            'Failed to load files',
                            style: TextStyle(fontSize: 14, color: Colors.red.shade300),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${snap.error}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 11, color: Colors.white54),
                          ),
                          const SizedBox(height: 12),
                          FilledButton.tonal(
                            onPressed: _reload,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                if (snap.data!.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.folder_open, size: 48, color: Colors.white24),
                          const SizedBox(height: 12),
                          const Text(
                            'No files yet',
                            style: TextStyle(fontSize: 14, color: Colors.white70),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Create a file or folder to get started',
                            style: TextStyle(fontSize: 11, color: Colors.white38),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return ListView(
                  children: [
                    for (final entry in snap.data!)
                      _EntryTile(
                        key: ValueKey(entry.path),
                        fs: widget.fs,
                        entry: entry,
                        depth: 0,
                        onFileTap: widget.onFileTap,
                        onChanged: _reload,
                        onExtractArchive: (path) =>
                            _extractArchive(path, widget.fs, context, _reload),
                        activeFile: widget.activeFile,
                        expandedDirs: _expandedDirs,
                        onToggleDir: _onToggleDir,
                        selectedDir: _selectedDir,
                        onSelectDir: _selectDir,
                        reloadGen: _reloadGen,
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    ),
        );
      },
    );
  }

  Future<void> _createEntry({required bool isFolder}) async {
    final target = _selectedDir;
    final name = await _promptName(
      'New ${isFolder ? 'folder' : 'file'}',
      isFolder ? 'src' : 'main.py',
      target: target,
    );
    if (name == null || name.isEmpty) return;
    if (name.contains('/') || name.contains('\\')) {
      _showError('Name cannot contain path separators');
      return;
    }
    final path = target == null ? name : '$target/$name';
    try {
      if (isFolder) {
        await widget.fs.createDirectory(path);
      } else {
        await widget.fs.createFile(path);
      }
      if (target != null) {
        _expandedDirs.add(target);
        widget.prefs?.saveExpanded(_expandedDirs);
      }
      if (mounted) {
        _reload();
      }
    } catch (e) {
      if (mounted) {
        _showError(e.toString());
      }
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message), backgroundColor: Colors.red.shade700));
  }

  void _createFromTemplate() {
    TemplateSelectorDialog.show(
      context,
      targetDir: _selectedDir ?? '.',
      fs: widget.fs,
      onCreated: _reload,
    );
  }

  Future<String?> _promptName(String title, String hint, {String? initial, String? target}) async {
    String text = initial ?? '';
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (target != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Inside $target',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            TextFormField(
              initialValue: text,
              autofocus: true,
              decoration: InputDecoration(hintText: hint),
              onChanged: (v) => text = v,
              onFieldSubmitted: (v) {
                FocusScope.of(context).unfocus();
                Navigator.pop(context, v.trim());
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              FocusScope.of(context).unfocus();
              Navigator.pop(context);
            }, 
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              FocusScope.of(context).unfocus();
              Navigator.pop(context, text.trim());
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
    return result;
  }
}

class _TargetBar extends StatelessWidget {
  final String target;
  final VoidCallback onClear;

  const _TargetBar({required this.target, required this.onClear});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 2),
      padding: const EdgeInsets.fromLTRB(10, 2, 2, 2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          Icon(Icons.subdirectory_arrow_right, size: 14, color: Colors.amber.shade300),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              target,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11.5, color: Colors.white70),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close, size: 14),
            color: Colors.white54,
            tooltip: 'Create at root instead',
            onPressed: onClear,
          ),
        ],
      ),
    );
  }
}

class _EntryTile extends StatefulWidget {
  final FsService fs;
  final FsEntry entry;
  final int depth;
  final ValueChanged<String> onFileTap;
  final VoidCallback onChanged;
  final Future<bool> Function(String) onExtractArchive;
  final String? activeFile;
  final Set<String> expandedDirs;
  final void Function(String relativePath, bool expanded) onToggleDir;
  final String? selectedDir;
  final void Function(String relativePath) onSelectDir;
  final int reloadGen;

  const _EntryTile({
    super.key,
    required this.fs,
    required this.entry,
    required this.depth,
    required this.onFileTap,
    required this.onChanged,
    required this.onExtractArchive,
    required this.expandedDirs,
    required this.onToggleDir,
    required this.onSelectDir,
    required this.reloadGen,
    this.activeFile,
    this.selectedDir,
  });

  @override
  State<_EntryTile> createState() => _EntryTileState();
}

class _EntryTileState extends State<_EntryTile> {
  late bool _expanded;
  Future<List<FsEntry>>? _childrenFuture;

  FsService get fs => widget.fs;
  FsEntry get entry => widget.entry;
  String get _relativePath => fs.relativeToRoot(entry.path);

  @override
  void initState() {
    super.initState();
    _expanded = widget.expandedDirs.contains(_relativePath);
    if (_expanded) {
      _childrenFuture = fs.list(_relativePath);
    }
  }

  @override
  void didUpdateWidget(_EntryTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    _expanded = widget.expandedDirs.contains(_relativePath);
    if (_expanded &&
        (widget.reloadGen != oldWidget.reloadGen || _childrenFuture == null)) {
      _childrenFuture = fs.list(_relativePath);
    }
  }

  void _toggle() {
    final expanded = !_expanded;
    setState(() {
      _expanded = expanded;
      if (expanded) {
        _childrenFuture = fs.list(_relativePath, refresh: true);
      }
    });
    widget.onToggleDir(_relativePath, expanded);
  }

  void _reloadSubtree() {
    if (_expanded) {
      setState(() => _childrenFuture = fs.list(_relativePath, refresh: true));
    }
    widget.onChanged();
  }

  Widget get _leadingIcon {
    if (entry.isDirectory) {
      return FileTypeIcon(spec: folderSpec(entry.name, _expanded), size: 18);
    }
    return FileTypeIcon(spec: fileSpec(entry.name), size: 18);
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.activeFile == entry.path;
    final isArchive =
        !entry.isDirectory && ArchiveExtractor.isArchiveName(entry.name);
    final isSelectedTarget =
        entry.isDirectory && widget.selectedDir == _relativePath;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          contentPadding:
              EdgeInsets.only(left: 12.0 + widget.depth * 16, right: 4),
          dense: true,
          tileColor: isSelectedTarget
              ? Colors.white.withValues(alpha: 0.08)
              : null,
          shape: isSelectedTarget
              ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))
              : null,
          leading: _leadingIcon,
          title: Text(
            entry.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          selected: selected,
          onTap: () {
            if (entry.isDirectory) {
              widget.onSelectDir(_relativePath);
              _toggle();
            } else {
              widget.onFileTap(entry.path);
            }
          },
          trailing: PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 18),
            tooltip: 'Options for ${entry.name}',
            onSelected: (action) => _handleAction(context, action),
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'copy_path', child: Text('Copy Path')),
              if (!entry.isDirectory)
                const PopupMenuItem(
                    value: 'export', child: Text('Export to device…')),
              if (isArchive)
                const PopupMenuItem(
                    value: 'extract_archive', child: Text('Extract Archive')),
              const PopupMenuItem(value: 'rename', child: Text('Rename')),
              const PopupMenuItem(value: 'move', child: Text('Move…')),
              const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ),
        if (_expanded && entry.isDirectory)
          FutureBuilder<List<FsEntry>>(
            future: _childrenFuture,
            builder: (context, snap) {
              if (!snap.hasData) return const SizedBox.shrink();
              return Column(
                children: [
                  for (final child in snap.data!)
                    _EntryTile(
                      key: ValueKey(child.path),
                      fs: fs,
                      entry: child,
                      depth: widget.depth + 1,
                      onFileTap: widget.onFileTap,
                      onChanged: _reloadSubtree,
                      onExtractArchive: widget.onExtractArchive,
                      activeFile: widget.activeFile,
                      expandedDirs: widget.expandedDirs,
                      onToggleDir: widget.onToggleDir,
                      selectedDir: widget.selectedDir,
                      onSelectDir: widget.onSelectDir,
                      reloadGen: widget.reloadGen,
                    ),
                ],
              );
            },
          ),
      ],
    );
  }

  Future<void> _handleAction(BuildContext context, String action) async {
    try {
      switch (action) {
        case 'copy_path':
          await Clipboard.setData(ClipboardData(text: entry.path));
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Copied: ${entry.path}')),
            );
          }
          break;
        case 'export':
          await exportFileToDevice(context, entry.path);
          break;
        case 'extract_archive':
          await widget.onExtractArchive(entry.path);
          break;
        case 'rename':
          String text = entry.name;
          final newName = await showDialog<String>(
            context: context,
            builder: (ctx) {
              return AlertDialog(
                title: const Text('Rename'),
                content: TextFormField(
                  initialValue: text, 
                  autofocus: true,
                  onChanged: (v) => text = v,
                  onFieldSubmitted: (v) {
                    FocusScope.of(ctx).unfocus();
                    Navigator.pop(ctx, v.trim());
                  },
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      FocusScope.of(ctx).unfocus();
                      Navigator.pop(ctx);
                    }, 
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () {
                      FocusScope.of(ctx).unfocus();
                      Navigator.pop(ctx, text.trim());
                    },
                    child: const Text('Rename'),
                  ),
                ],
              );
            },
          );
          if (newName != null && newName.isNotEmpty && newName != entry.name) {
            await fs.rename(entry.path, newName);
            final newPath = p.join(p.dirname(entry.path), newName);
            sl<TabManager>().handleFileRenamed(entry.path, newPath);
            _reloadSubtree();
          }
        case 'move':
          final target = await showDialog<String>(
            context: context,
            builder: (_) => FolderPickerDialog(fs: fs),
          );
          if (target != null) {
            await fs.move(entry.path, target);
            final newPath = p.join(target, entry.name);
            sl<TabManager>().handleFileRenamed(entry.path, newPath);
            _reloadSubtree();
          }
        case 'delete':
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Delete'),
              content: Text('Delete "${entry.name}"${entry.isDirectory ? ' and all contents' : ''}?'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: FilledButton.styleFrom(backgroundColor: Colors.red),
                  child: const Text('Delete'),
                ),
              ],
            ),
          );
          if (confirmed == true) {
            await fs.delete(entry.path);
            sl<TabManager>().handleFileDeleted(entry.path);
            _reloadSubtree();
          }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: Colors.red));
      }
    }
  }
}

class FolderPickerDialog extends StatefulWidget {
  final FsService fs;

  const FolderPickerDialog({super.key, required this.fs});

  @override
  State<FolderPickerDialog> createState() => _FolderPickerDialogState();
}

class _FolderPickerDialogState extends State<FolderPickerDialog> {
  String current = '.';
  List<FsEntry> entries = [];

  @override
  void initState() {
    super.initState();
    current = widget.fs.rootPath;
    _load();
  }

  Future<void> _load() async {
    try {
      final relPath = current == widget.fs.rootPath ? '.' : widget.fs.relativeToRoot(current);
      final list = (await widget.fs.list(relPath)).where((e) => e.isDirectory).toList();
      if (!mounted) return;
      setState(() => entries = list);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to load folders: $e'), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Move to folder'),
      content: SizedBox(
        width: 280,
        height: 320,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(current, style: Theme.of(context).textTheme.bodySmall),
            const Divider(),
            Expanded(
              child: ListView(
                children: [
if (current != widget.fs.rootPath)
                      ListTile(
                        leading: const Icon(Icons.arrow_upward, size: 18),
                        dense: true,
                        title: const Text('..'),
                        onTap: () {
                          setState(() {
                            current = p.dirname(current);
                            if (current == widget.fs.rootPath) {
                              current = widget.fs.rootPath;
                            }
                          });
                          _load();
                        },
                      ),
                    for (final e in entries)
                      ListTile(
                        leading: const Icon(Icons.folder_outlined, size: 18),
                        dense: true,
                        title: Text(e.name),
                        onTap: () {
                          setState(() =>
                              current = p.join(current, e.name));
                          _load();
                        },
                      ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, current), child: const Text('Move here')),
      ],
    );
  }
}
