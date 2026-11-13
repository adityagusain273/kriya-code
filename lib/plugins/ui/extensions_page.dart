import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/di.dart';
import '../../editor/highlighting/highlight_engine.dart';
import '../../editor/tab_manager.dart';
import '../../execution/runtime_download_service.dart';
import '../../execution/ui/downloads_page.dart';
import '../../workspace/device_import_service.dart';
import '../../workspace/fs_service.dart';
import '../../workspace/import_actions.dart';
import '../../workspace/mdi.dart';
import '../host/extension_install_store.dart';
import '../packages/extension_installer.dart';
import '../packages/extension_loader.dart';
import '../packages/extension_manifest.dart';
import '../packages/extension_scaffold.dart';
import '../packages/extension_source.dart';

class _ExtUi {
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final String? runtimeId;

  const _ExtUi({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.runtimeId,
  });
}

const _extensions = <_ExtUi>[
  _ExtUi(
    id: 'bcode.lang.python',
    title: 'Python',
    subtitle: 'Python language pack — highlighting, run support',
    icon: Icons.code_rounded,
    runtimeId: 'cpython',
  ),
  _ExtUi(
    id: 'bcode.lang.java',
    title: 'Java',
    subtitle: 'Java language pack — highlighting, run support',
    icon: Icons.local_cafe_rounded,
    runtimeId: 'openjdk',
  ),
  _ExtUi(
    id: 'bcode.lang.c',
    title: 'C',
    subtitle: 'C language pack — highlighting and run support',
    icon: Icons.code_rounded,
    runtimeId: 'clang',
  ),
  _ExtUi(
    id: 'bcode.lang.cpp',
    title: 'C++',
    subtitle: 'C++ language pack — highlighting and run support',
    icon: Icons.code_rounded,
    runtimeId: 'clang',
  ),
  _ExtUi(
    id: 'bcode.lang.javascript',
    title: 'JavaScript',
    subtitle: 'JavaScript language pack — highlighting, run support',
    icon: Mdi.languageJavascript,
    runtimeId: 'nodejs',
  ),
  _ExtUi(
    id: 'bcode.lang.typescript',
    title: 'TypeScript',
    subtitle: 'TypeScript language pack — highlighting',
    icon: Mdi.languageTypescript,
  ),
  _ExtUi(
    id: 'bcode.lang.html',
    title: 'HTML',
    subtitle: 'HTML language pack — highlighting and live preview',
    icon: Mdi.languageHtml5,
  ),
  _ExtUi(
    id: 'bcode.lang.css',
    title: 'CSS',
    subtitle: 'CSS language pack — highlighting for stylesheets',
    icon: Mdi.languageCss3,
  ),
  _ExtUi(
    id: 'bcode.lang.json',
    title: 'JSON',
    subtitle: 'JSON language pack — highlighting and validation',
    icon: Mdi.codeJson,
  ),
  _ExtUi(
    id: 'bcode.lang.markdown',
    title: 'Markdown',
    subtitle: 'Markdown language pack — GitHub-flavored syntax highlighting',
    icon: Icons.description_outlined,
  ),
  _ExtUi(
    id: 'bcode.github',
    title: 'GitHub',
    subtitle: 'Clone, commit, push and sync repositories',
    icon: Icons.account_tree_outlined,
  ),
  _ExtUi(
    id: 'bcode.termux',
    title: 'Termux',
    subtitle: 'Device shell integration for local toolchains',
    icon: Icons.terminal_outlined,
  ),
  _ExtUi(
    id: 'bcode.zoom',
    title: 'Pinch to Zoom',
    subtitle: 'Zoom in and out in the editor for comfortable code reading',
    icon: Icons.zoom_in_rounded,
  ),
  _ExtUi(
    id: 'bcode.live_server',
    title: 'Live Server',
    subtitle: 'Local dev server with live reload for HTML, CSS, and JS',
    icon: Icons.play_circle_outline_rounded,
  ),
  _ExtUi(
    id: 'bcode.icons.material',
    title: 'Material Icon Theme',
    subtitle: 'Beautiful file and folder icons for your workspace',
    icon: Icons.color_lens_outlined,
  ),
];

class ExtensionsPage extends StatefulWidget {
  const ExtensionsPage({super.key});

  @override
  State<ExtensionsPage> createState() => _ExtensionsPageState();
}

class _ExtensionsPageState extends State<ExtensionsPage> {
  ExtensionInstallStore get _store => sl<ExtensionInstallStore>();
  RuntimeDownloadService get _downloads => sl<RuntimeDownloadService>();

  ExtensionInstaller? get _installer =>
      sl.isRegistered<ExtensionInstaller>() ? sl<ExtensionInstaller>() : null;

  ExtensionSourceService? get _sources =>
      sl.isRegistered<ExtensionSourceService>()
          ? sl<ExtensionSourceService>()
          : null;

  final TextEditingController _searchController = TextEditingController();
  bool _searchVisible = false;
  String _query = '';
  bool _busy = false;
  bool _loadingCatalog = false;
  List<InstalledExtension> _installed = const [];
  List<ExtensionCatalogEntry> _catalog = const [];
  Map<String, String> _sourceErrors = const {};

  @override
  void initState() {
    super.initState();
    _refreshInstalled();
    _refreshCatalog();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<_ExtUi> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _extensions;
    return _extensions
        .where((e) =>
            e.title.toLowerCase().contains(q) ||
            e.subtitle.toLowerCase().contains(q) ||
            e.id.toLowerCase().contains(q))
        .toList();
  }

  List<InstalledExtension> get _filteredInstalled {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _installed;
    return _installed
        .where((e) =>
            e.manifest.name.toLowerCase().contains(q) ||
            e.manifest.id.toLowerCase().contains(q) ||
            e.manifest.description.toLowerCase().contains(q))
        .toList();
  }

  List<ExtensionCatalogEntry> get _filteredCatalog {
    final q = _query.trim().toLowerCase();
    final installed = {
      for (final extension in _installed)
        extension.manifest.id: extension.manifest.version,
    };
    return _catalog.where((e) {
      if (installed[e.id] == e.version) return false;
      if (q.isEmpty) return true;
      return e.name.toLowerCase().contains(q) ||
          e.id.toLowerCase().contains(q) ||
          e.description.toLowerCase().contains(q);
    }).toList();
  }

  void _toggleSearch() {
    setState(() {
      _searchVisible = !_searchVisible;
      if (!_searchVisible) {
        _query = '';
        _searchController.clear();
      }
    });
  }

  void _openDownloads({String? runtimeId}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DownloadsPage(focusRuntimeId: runtimeId),
      ),
    );
  }

  Future<void> _refreshInstalled() async {
    final installer = _installer;
    if (installer == null) return;
    try {
      final list = await installer.installed();
      if (mounted) setState(() => _installed = list);
    } catch (_) {
      // installed() already skips unreadable packages; a directory-level
      // failure only means the list stays as it was.
    }
  }

  Future<void> _refreshCatalog() async {
    final sources = _sources;
    if (sources == null || sources.sources.isEmpty) return;
    if (!mounted) return;
    setState(() => _loadingCatalog = true);
    try {
      final result = await sources.browse();
      if (mounted) {
        setState(() {
          _catalog = result.entries;
          _sourceErrors = result.errors;
        });
      }
    } finally {
      if (mounted) setState(() => _loadingCatalog = false);
    }
  }

  Future<void> _onInstallTap(_ExtUi ext) async {
    final installed = _store.isInstalled(ext.id);
    if (installed) {
      setState(() => _store.uninstall(ext.id));
      // Do NOT delete the runtime here. C and C++ share the `clang` runtime,
      // and deleting it on uninstall of either broke the other. Runtimes are
      // managed on the Downloads page.
      return;
    }

    final runtimeId = ext.runtimeId;
    if (runtimeId != null) {
      try {
        await _downloads.download(runtimeId);
        final state = _downloads.stateFor(runtimeId);
        if (state.phase != RuntimeDownloadPhase.installed) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: Text(
                      'Download failed: ${state.error ?? "unknown error"}')),
            );
          }
          return;
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to download runtime: $e')),
          );
        }
        return;
      }
    }
    if (mounted) {
      setState(() => _store.install(ext.id));
    }
  }

  Future<void> _installFile() async {
    final installer = _installer;
    if (installer == null) return;
    final picked = await importFileFromDevice(context);
    if (picked == null || !mounted) return;

    final file = File(picked.path);
    try {
      await _stageAndInstall(() => installer.stageArchive(file));
    } finally {
      await file.delete().catchError((_) => file);
    }
  }

  Future<void> _installFromUrl([String? url]) async {
    final installer = _installer;
    if (installer == null) return;
    final target = url ??
        await _textDialog(
          title: 'Install from URL',
          hint: 'https://example.com/my-extension.bcext',
          help: 'Any HTTPS link to a .bcext file. Unlisted links stay private.',
        );
    if (target == null || target.isEmpty || !mounted) return;
    await _stageAndInstall(() => installer.stageUrl(target));
  }

  Future<void> _stageAndInstall(
    Future<StagedExtension> Function() stage,
  ) async {
    final installer = _installer;
    if (installer == null) return;
    setState(() => _busy = true);
    StagedExtension? staged;
    try {
      staged = await stage();
      if (!mounted) return;
      if (!await _confirmInstall(staged)) {
        await installer.discard(staged);
        return;
      }
      final extension = await installer.commit(staged);
      staged = null;
      if (sl.isRegistered<ExtensionLoader>()) {
        sl<ExtensionLoader>().activateOne(extension);
      } else if (sl.isRegistered<HighlightEngine>()) {
        activateExtensions([extension], engine: sl<HighlightEngine>());
      }
      await _refreshInstalled();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Installed ${extension.manifest.name} ${extension.manifest.version}.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not install: $error')),
      );
    } finally {
      if (staged != null) await installer.discard(staged);
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirmInstall(
    StagedExtension staged, {
    String? title,
    String confirmLabel = 'Install',
    bool showReadme = true,
  }) async {
    final manifest = staged.manifest;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        return AlertDialog(
          title: Text(title ?? 'Install ${manifest.name}?'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (manifest.version.isNotEmpty)
                    Text('Version ${manifest.version}'),
                  if (manifest.author.isNotEmpty)
                    Text('By ${manifest.author}'),
                  if (manifest.description.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(manifest.description),
                  ],
                  if (manifest.languages.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text('Languages', style: theme.textTheme.titleSmall),
                    for (final language in manifest.languages)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '${language.name} (${language.extensions.map((ext) => '.$ext').join(', ')})',
                        ),
                      ),
                  ],
                  const SizedBox(height: 16),
                  Text(
                    '${staged.snippetCount} snippet(s) · '
                    '${manifest.themes.length} theme(s)',
                    style: theme.textTheme.bodySmall,
                  ),
                  if (staged.readme != null && showReadme) ...[
                    const SizedBox(height: 16),
                    Text('README', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 4),
                    Text(
                      staged.readme!,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(confirmLabel),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  Future<void> _installUnpacked() async {
    final installer = _installer;
    if (installer == null) return;
    final chosen = await _pickExtensionFolder('Load unpacked extension');
    if (chosen == null || !mounted) return;
    await _stageAndInstall(() => installer.stageDirectory(chosen));
  }

  Future<void> _exportExtension() async {
    final installer = _installer;
    if (installer == null || !sl.isRegistered<FsService>()) return;
    final chosen = await _pickExtensionFolder('Export .bcext');
    if (chosen == null || !mounted) return;

    final fs = sl<FsService>();
    final manifest = ExtensionManifest.parse(
      await File(p.join(chosen, 'extension.json')).readAsString(),
    );
    final target = fs.resolve('${manifest.id}-${manifest.version}.bcext');
    final readmeFile = File(p.join(chosen, 'README.md'));
    final readme = await readmeFile.exists() ? await readmeFile.readAsString() : null;
    if (!mounted) return;
    final preview = StagedExtension(
      manifest: manifest,
      directory: chosen,
      container: chosen,
      readme: readme,
    );
    final messenger = ScaffoldMessenger.of(context);
    try {
      final name = await installer.packageDirectory(chosen, target);
      if (!mounted) return;
      if (!await _confirmInstall(
        preview,
        title: 'Share ${manifest.name}?',
        confirmLabel: 'Export',
        showReadme: false,
      )) {
        await File(target).delete();
        return;
      }
      final exported = await DeviceImportService.instance.exportFile(target);
      if (exported) {
        await File(target).delete();
      } else {
        messenger.showSnackBar(
          SnackBar(content: Text('Package kept at $name')),
        );
      }
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not package the extension: $error')),
      );
    }
  }

  Future<String?> _pickExtensionFolder(String title) async {
    if (!sl.isRegistered<FsService>()) return null;
    final fs = sl<FsService>();
    final folders = (await fs.list(ExtensionScaffold.folder, refresh: true))
        .where((entry) => entry.isDirectory)
        .toList();
    if (!mounted) return null;

    if (folders.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('No folders in extensions/. Create an extension first.'),
        ),
      );
      return null;
    }

    return showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(title),
        children: [
          for (final folder in folders)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, folder.path),
              child: Text(folder.name),
            ),
        ],
      ),
    );
  }

  Future<void> _createExtension() async {
    if (!sl.isRegistered<FsService>()) return;
    try {
      final path = await ExtensionScaffold.create(sl<FsService>());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Created $path. Edit it, then Load unpacked.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not create the extension: $error')),
      );
    }
  }

  Future<void> _removeExtension(InstalledExtension extension) async {
    final installer = _installer;
    if (installer == null) return;
    try {
      await installer.uninstall(extension.manifest.id);
      final registration = sl.isRegistered<ExtensionLoader>()
          ? sl<ExtensionLoader>().deactivate(extension.manifest.id)
          : null;
      if (registration != null &&
          registration.languageIds.isNotEmpty &&
          sl.isRegistered<TabManager>()) {
        sl<TabManager>().dropLanguages(registration.languageIds);
      }
      await _refreshInstalled();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Removed ${extension.manifest.name}.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not remove: $error')),
      );
    }
  }

  Future<void> _addSource() async {
    final sources = _sources;
    if (sources == null) return;
    final url = await _textDialog(
      title: 'Add extension source',
      hint: ExtensionSourceService.defaultSource,
      help: 'An index lists public extensions. Anyone can host one.',
    );
    if (url == null || url.isEmpty || !mounted) return;
    try {
      await sources.addSource(url);
      await _refreshCatalog();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not add that source: $error')),
      );
    }
  }

  Future<void> _manageSources() async {
    final sources = _sources;
    if (sources == null) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Extension sources'),
          content: sources.sources.isEmpty
              ? const Text(
                  'No sources yet. Add an index URL to browse public extensions.')
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final source in sources.sources)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title:
                            Text(source, style: const TextStyle(fontSize: 12)),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: 'Remove source',
                          onPressed: () async {
                            await sources.removeSource(source);
                            if (context.mounted) setDialogState(() {});
                            await _refreshCatalog();
                          },
                        ),
                      ),
                  ],
                ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                _addSource();
              },
              child: const Text('Add source'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _textDialog({
    required String title,
    required String hint,
    required String help,
  }) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                hintText: hint,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Text(help, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final results = _filtered;
    final theme = Theme.of(context);
    final hasCommunity = _sources != null ||
        _installed.isNotEmpty ||
        _catalog.isNotEmpty ||
        _loadingCatalog;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Extensions'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Search extensions',
            onPressed: _toggleSearch,
          ),
          IconButton(
            icon: const Icon(Icons.download_rounded),
            tooltip: 'Downloads',
            onPressed: _openDownloads,
          ),
          PopupMenuButton<String>(
            tooltip: 'Extension actions',
            onSelected: (value) {
              switch (value) {
                case 'file':
                  _installFile();
                case 'url':
                  _installFromUrl();
                case 'unpacked':
                  _installUnpacked();
                case 'export':
                  _exportExtension();
                case 'create':
                  _createExtension();
                case 'source':
                  _addSource();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'file', child: Text('Install from file')),
              PopupMenuItem(value: 'url', child: Text('Install from URL')),
              PopupMenuItem(value: 'unpacked', child: Text('Load unpacked')),
              PopupMenuItem(value: 'export', child: Text('Export .bcext')),
              PopupMenuDivider(),
              PopupMenuItem(value: 'create', child: Text('Create extension')),
              PopupMenuItem(
                  value: 'source', child: Text('Add extension source')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          if (_searchVisible)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Search by name…',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.close, size: 16),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                        ),
                  border: const OutlineInputBorder(),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
          Expanded(
            child: ListView(
              children: [
                if (hasCommunity) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 8, 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Community extensions',
                            style: theme.textTheme.titleSmall,
                          ),
                        ),
                        TextButton(
                          onPressed: _manageSources,
                          child: const Text('Sources'),
                        ),
                      ],
                    ),
                  ),
                  if (_loadingCatalog)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  for (final ext in _filteredInstalled)
                    _CommunityCard(
                      title: ext.manifest.name,
                      subtitle: _describe(
                        ext.manifest.version,
                        ext.manifest.author,
                        ext.manifest.description,
                      ),
                      installed: true,
                      onTap: () => _removeExtension(ext),
                    ),
                  for (final entry in _filteredCatalog)
                    _CommunityCard(
                      title: entry.name,
                      subtitle: _describe(
                        entry.version,
                        entry.author,
                        entry.description,
                      ),
                      installed: false,
                      actionLabel:
                          _installed.any((ext) => ext.manifest.id == entry.id)
                              ? 'Update'
                              : 'Get',
                      onTap: () => _installFromUrl(entry.download),
                    ),
                  if (_sourceErrors.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                      child: Text(
                        '${_sourceErrors.length} source(s) could not be loaded. '
                        'Check the URL in Sources, or install a .bcext directly.',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.error),
                      ),
                    ),
                  if (_sources?.sources.isEmpty ?? false)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                      child: Text(
                        'No sources. Add an index URL to browse public extensions, '
                        'or install a .bcext file directly. Community packages add '
                        'highlighting, snippets and themes — they cannot execute code.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                ],
                if (results.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                    child: Text('Bundled', style: theme.textTheme.titleSmall),
                  ),
                if (results.isEmpty && _query.trim().isNotEmpty)
                  _EmptySearchState(query: _query.trim())
                else
                  for (final ext in results)
                    _ExtensionCard(
                      ext: ext,
                      installed: _store.isInstalled(ext.id),
                      onTap: () => _onInstallTap(ext),
                      downloads: _downloads,
                    ),
                if (_query.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Language packs include a downloadable runtime so you can keep '
                      'coding offline. Downloads are fetched from the Termux package '
                      'repository.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _describe(String version, String author, String description) {
    final parts = <String>[
      if (version.isNotEmpty) 'v$version',
      if (author.isNotEmpty) 'by $author',
      if (description.isNotEmpty) description,
    ];
    return parts.join(' · ');
  }
}

class _CommunityCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool installed;
  final String actionLabel;
  final VoidCallback onTap;

  const _CommunityCard({
    required this.title,
    required this.subtitle,
    required this.installed,
    required this.onTap,
    this.actionLabel = 'Get',
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ListTile(
        leading: Icon(
          installed ? Icons.extension_rounded : Icons.add_box_outlined,
          size: 28,
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          subtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12),
        ),
        trailing: installed
            ? OutlinedButton(
                onPressed: onTap,
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                child: const Text('Remove'),
              )
            : FilledButton.tonal(
                onPressed: onTap,
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                child: Text(actionLabel),
              ),
      ),
    );
  }
}

class _EmptySearchState extends StatelessWidget {
  final String query;

  const _EmptySearchState({required this.query});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.search_off_rounded, size: 40, color: Colors.white24),
          const SizedBox(height: 8),
          Text(
            query.isEmpty
                ? 'Type a name to search'
                : 'No extensions found for "$query"',
            style: const TextStyle(fontSize: 13, color: Colors.white54),
          ),
        ],
      ),
    );
  }
}

class _ExtensionCard extends StatelessWidget {
  final _ExtUi ext;
  final bool installed;
  final VoidCallback onTap;
  final RuntimeDownloadService downloads;

  const _ExtensionCard({
    required this.ext,
    required this.installed,
    required this.onTap,
    required this.downloads,
  });

  @override
  Widget build(BuildContext context) {
    final runtimeId = ext.runtimeId;
    return ListenableBuilder(
      listenable: downloads,
      builder: (context, _) {
        final state = runtimeId != null ? downloads.stateFor(runtimeId) : null;
        final isDownloading = state != null &&
            (state.phase == RuntimeDownloadPhase.resolving ||
                state.phase == RuntimeDownloadPhase.downloading ||
                state.phase == RuntimeDownloadPhase.installing);

        Widget trailing;
        if (isDownloading) {
          final progress = state.progress;
          trailing = SizedBox(
            width: 100,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                LinearProgressIndicator(value: progress),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      state.phase == RuntimeDownloadPhase.downloading
                          ? (progress != null
                              ? '${(progress * 100).toInt()}%'
                              : 'Downloading...')
                          : state.phase.name,
                      style: const TextStyle(fontSize: 10),
                    ),
                    if (runtimeId != null) ...[
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: () => downloads.cancel(runtimeId),
                        child: Icon(Icons.cancel_rounded,
                            size: 16, color: Colors.red.shade300),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          );
        } else if (installed) {
          trailing = FilledButton.tonalIcon(
            onPressed: onTap,
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('Delete'),
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              foregroundColor: Colors.red.shade300,
            ),
          );
        } else {
          trailing = FilledButton.icon(
            onPressed: onTap,
            icon: const Icon(Icons.download_rounded, size: 18),
            label: const Text('Install'),
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
            ),
          );
        }

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: ListTile(
            leading: Icon(ext.icon, size: 28),
            title: Text(ext.title,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(ext.subtitle, style: const TextStyle(fontSize: 12)),
            trailing: trailing,
            onTap: runtimeId == null
                ? null
                : () {
                    if (installed) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              DownloadsPage(focusRuntimeId: runtimeId),
                        ),
                      );
                    }
                  },
          ),
        );
      },
    );
  }
}
