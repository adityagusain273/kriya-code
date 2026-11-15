import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/di.dart';
import '../../editor/highlighting/highlight_engine.dart';
import '../../editor/tab_manager.dart';
import '../../execution/runtime_download_service.dart';
import '../../execution/ui/downloads_page.dart';
import '../../monetization/entitlement_service.dart';
import '../../monetization/pro_paywall_sheet.dart';
import '../../monetization/runtime_unlock_flow.dart';
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
  final String description;
  final IconData icon;
  final Color color;
  final String version = '1.0.0';
  final String? runtimeId;

  const _ExtUi({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    this.runtimeId,
  });
}

const _extensions = <_ExtUi>[
  _ExtUi(
    id: 'bcode.lang.python',
    title: 'Python',
    description: 'Python language pack — highlighting, run support',
    icon: Icons.code_rounded,
    color: Color(0xFF3B7EA1),
    runtimeId: 'cpython',
  ),
  _ExtUi(
    id: 'bcode.lang.java',
    title: 'Java',
    description: 'Java language pack — highlighting, run support',
    icon: Icons.local_cafe_rounded,
    color: Color(0xFFC25E00),
    runtimeId: 'openjdk',
  ),
  _ExtUi(
    id: 'bcode.lang.c',
    title: 'C',
    description: 'C language pack — highlighting and run support',
    icon: Icons.code_rounded,
    color: Color(0xFF4A7FC1),
    runtimeId: 'clang',
  ),
  _ExtUi(
    id: 'bcode.lang.cpp',
    title: 'C++',
    description: 'C++ language pack — highlighting and run support',
    icon: Icons.code_rounded,
    color: Color(0xFF2F6FB0),
    runtimeId: 'clang',
  ),
  _ExtUi(
    id: 'bcode.lang.javascript',
    title: 'JavaScript',
    description: 'JavaScript language pack — highlighting, run support',
    icon: Mdi.languageJavascript,
    color: Color(0xFFB8860B),
    runtimeId: 'nodejs',
  ),
  _ExtUi(
    id: 'bcode.lang.typescript',
    title: 'TypeScript',
    description: 'TypeScript language pack — highlighting',
    icon: Mdi.languageTypescript,
    color: Color(0xFF3178C6),
  ),
  _ExtUi(
    id: 'bcode.lang.html',
    title: 'HTML',
    description: 'HTML language pack — highlighting and live preview',
    icon: Mdi.languageHtml5,
    color: Color(0xFFD84315),
  ),
  _ExtUi(
    id: 'bcode.lang.css',
    title: 'CSS',
    description: 'CSS language pack — highlighting for stylesheets',
    icon: Mdi.languageCss3,
    color: Color(0xFF2A6FB0),
  ),
  _ExtUi(
    id: 'bcode.lang.json',
    title: 'JSON',
    description: 'JSON language pack — highlighting and validation',
    icon: Mdi.codeJson,
    color: Color(0xFF6B7B8C),
  ),
  _ExtUi(
    id: 'bcode.lang.markdown',
    title: 'Markdown',
    description: 'Markdown language pack — GitHub-flavored syntax highlighting',
    icon: Icons.description_outlined,
    color: Color(0xFF5F7183),
  ),
  _ExtUi(
    id: 'bcode.github',
    title: 'GitHub',
    description: 'Clone, commit, push and sync repositories',
    icon: Icons.account_tree_outlined,
    color: Color(0xFF7B8794),
  ),
  _ExtUi(
    id: 'bcode.termux',
    title: 'Termux',
    description: 'Device shell integration for local toolchains',
    icon: Icons.terminal_outlined,
    color: Color(0xFF00897B),
  ),
  _ExtUi(
    id: 'bcode.zoom',
    title: 'Pinch to Zoom',
    description: 'Zoom in and out in the editor for comfortable code reading',
    icon: Icons.zoom_in_rounded,
    color: Color(0xFF1E88E5),
  ),
  _ExtUi(
    id: 'bcode.live_server',
    title: 'Live Server',
    description: 'Local dev server with live reload for HTML, CSS, and JS',
    icon: Icons.play_circle_outline_rounded,
    color: Color(0xFFE53935),
  ),
  _ExtUi(
    id: 'bcode.icons.material',
    title: 'Material Icon Theme',
    description: 'Beautiful file and folder icons for your workspace',
    icon: Icons.color_lens_outlined,
    color: Color(0xFF8E24AA),
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

  EntitlementService? get _entitlements =>
      sl.isRegistered<EntitlementService>() ? sl<EntitlementService>() : null;

  bool _isUnlocked(String id, [String? runtimeId]) {
    final entitlements = _entitlements;
    if (entitlements == null) return true;
    if (entitlements.isExtensionUnlocked(id)) return true;
    if (runtimeId != null && entitlements.isRuntimeUnlocked(runtimeId)) {
      return true;
    }
    return false;
  }

  Future<void> _onExploreBundledTap(_ExtUi ext) async {
    if (!_isUnlocked(ext.id, ext.runtimeId)) {
      final unlocked = await ensureExtensionUnlocked(
        context,
        extensionId: ext.id,
        extensionTitle: ext.title,
        runtimeId: ext.runtimeId,
      );
      if (!unlocked || !mounted) return;
      setState(() {});
    }
    await _onInstallTap(ext);
  }

  Future<void> _onCatalogTap(ExtensionCatalogEntry entry) async {
    if (!_isUnlocked(entry.id)) {
      final unlocked = await ensureExtensionUnlocked(
        context,
        extensionId: entry.id,
        extensionTitle: entry.name,
      );
      if (!unlocked || !mounted) return;
      setState(() {});
    }
    await _installFromUrl(entry.download);
  }

  final TextEditingController _searchController = TextEditingController();
  bool _exploreOpen = true;
  bool _installedOpen = true;
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
            e.description.toLowerCase().contains(q) ||
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
                  if (manifest.author.isNotEmpty) Text('By ${manifest.author}'),
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
    final readme =
        await readmeFile.exists() ? await readmeFile.readAsString() : null;
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
    final theme = Theme.of(context);
    final results = _filtered;
    final installedBundled =
        results.where((ext) => _store.isInstalled(ext.id)).toList();
    final exploreBundled =
        results.where((ext) => !_store.isInstalled(ext.id)).toList();
    final installed = _filteredInstalled;
    final catalog = _filteredCatalog;
    final exploreCount = catalog.length + exploreBundled.length;
    final installedCount = installed.length + installedBundled.length;
    final searching = _query.trim().isNotEmpty;
    final showExplore = !searching || exploreCount > 0;
    final showInstalled = !searching || installedCount > 0;

    final isPro = _entitlements?.isRuntimeUnlocked('') ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Extensions'),
        actions: [
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
                case 'sources':
                  _manageSources();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'file', child: Text('Install from file')),
              PopupMenuItem(value: 'url', child: Text('Install from URL')),
              PopupMenuItem(value: 'unpacked', child: Text('Load unpacked')),
              PopupMenuItem(value: 'export', child: Text('Export .bcext')),
              PopupMenuDivider(),
              PopupMenuItem(value: 'create', child: Text('Create extension')),
              PopupMenuItem(value: 'sources', child: Text('Manage sources')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (_busy || _loadingCatalog)
            const LinearProgressIndicator(minHeight: 2),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Search extensions',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                      ),
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHigh,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide:
                      BorderSide(color: theme.colorScheme.outlineVariant),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide:
                      BorderSide(color: theme.colorScheme.primary, width: 1.2),
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                if (!isPro && !searching)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: MissionBanner(
                      onGoAdFree: () async {
                        final activated = await showProPaywallSheet(context);
                        if (activated && mounted) setState(() {});
                      },
                    ),
                  ),
                if (showExplore) ...[
                  _SectionHeader(
                    title: 'Explore',
                    count: exploreCount,
                    expanded: _exploreOpen,
                    onTap: () => setState(() => _exploreOpen = !_exploreOpen),
                  ),
                  if (_exploreOpen) ...[
                    if (exploreCount == 0)
                      _EmptyLine(
                        _loadingCatalog
                            ? 'Loading community extensions…'
                            : searching
                                ? 'No matching extensions.'
                                : 'Everything is installed.',
                      )
                    else ...[
                      for (final entry in catalog) _catalogTile(entry),
                      for (final ext in exploreBundled) _bundledTile(ext),
                    ],
                    if (_sourceErrors.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                        child: Text(
                          '${_sourceErrors.length} source(s) could not be loaded. '
                          'Check the URL in Manage sources, or install a .bcext directly.',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colorScheme.error),
                        ),
                      ),
                    if (_sources?.sources.isEmpty ?? false)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'No sources yet. Add an index URL to browse community extensions.',
                              style: theme.textTheme.bodySmall,
                            ),
                            TextButton(
                              onPressed: _addSource,
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                visualDensity: VisualDensity.compact,
                              ),
                              child: const Text('Add source'),
                            ),
                          ],
                        ),
                      ),
                  ],
                ],
                if (showExplore && showInstalled) const SizedBox(height: 8),
                if (showInstalled) ...[
                  _SectionHeader(
                    title: 'Installed',
                    count: installedCount,
                    expanded: _installedOpen,
                    onTap: () =>
                        setState(() => _installedOpen = !_installedOpen),
                  ),
                  if (_installedOpen) ...[
                    if (installedCount == 0)
                      const _EmptyLine(
                        'Nothing installed yet. Download one from Explore.',
                      )
                    else ...[
                      for (final ext in installed) _communityTile(ext),
                      for (final ext in installedBundled) _bundledTile(ext),
                    ],
                  ],
                ],
                if (searching && exploreCount == 0 && installedCount == 0)
                  _EmptySearchState(query: _query.trim()),
                if (!searching)
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

  Widget _bundledTile(_ExtUi ext) {
    final installed = _store.isInstalled(ext.id);
    return ListenableBuilder(
      listenable: _downloads,
      builder: (context, _) {
        final runtimeId = ext.runtimeId;
        final state = runtimeId == null ? null : _downloads.stateFor(runtimeId);
        final downloading = state != null &&
            (state.phase == RuntimeDownloadPhase.resolving ||
                state.phase == RuntimeDownloadPhase.downloading ||
                state.phase == RuntimeDownloadPhase.installing);

        Widget trailing;
        if (downloading) {
          trailing = IconButton(
            tooltip: 'Cancel download',
            onPressed: () => _downloads.cancel(runtimeId!),
            icon: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                value: state.progress,
                strokeWidth: 2.5,
              ),
            ),
          );
        } else if (installed) {
          trailing = PopupMenuButton<String>(
            tooltip: 'Extension actions',
            icon: const Icon(Icons.more_vert, size: 20),
            onSelected: (value) {
              if (value == 'downloads') {
                _openDownloads(runtimeId: ext.runtimeId);
              } else {
                _onInstallTap(ext);
              }
            },
            itemBuilder: (_) => [
              if (ext.runtimeId != null)
                const PopupMenuItem(
                  value: 'downloads',
                  child: Text('Runtime downloads'),
                ),
              const PopupMenuItem(
                value: 'uninstall',
                child: Text('Uninstall'),
              ),
            ],
          );
        } else {
          final unlocked = _isUnlocked(ext.id, ext.runtimeId);
          if (!unlocked) {
            trailing = FilledButton.tonalIcon(
              icon: const Icon(Icons.lock_open_rounded, size: 14),
              label: const Text('Unlock', style: TextStyle(fontSize: 12)),
              style: FilledButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                visualDensity: VisualDensity.compact,
              ),
              onPressed: () => _onExploreBundledTap(ext),
            );
          } else {
            trailing = IconButton(
              tooltip: 'Install',
              onPressed: () => _onExploreBundledTap(ext),
              icon: const Icon(Icons.download_rounded, size: 22),
            );
          }
        }

        return _ExtensionTile(
          icon: ext.icon,
          color: ext.color,
          title: ext.title,
          meta: 'v${ext.version} · ${installed ? 'Installed' : 'Bundled'}',
          trailing: trailing,
          onTap: installed ? null : () => _onExploreBundledTap(ext),
        );
      },
    );
  }

  Widget _catalogTile(ExtensionCatalogEntry entry) {
    final updating = _installed.any((ext) => ext.manifest.id == entry.id);
    final author = entry.author.isEmpty ? '' : ' · by ${entry.author}';
    final unlocked = _isUnlocked(entry.id);

    Widget trailing;
    if (!unlocked && !updating) {
      trailing = FilledButton.tonalIcon(
        icon: const Icon(Icons.lock_open_rounded, size: 14),
        label: const Text('Unlock', style: TextStyle(fontSize: 12)),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
          visualDensity: VisualDensity.compact,
        ),
        onPressed: () => _onCatalogTap(entry),
      );
    } else {
      trailing = IconButton(
        tooltip: updating ? 'Update' : 'Install',
        onPressed: () => _onCatalogTap(entry),
        icon: const Icon(Icons.download_rounded, size: 22),
      );
    }

    return _ExtensionTile(
      letter: _initial(entry.name),
      color: _catalogColor(entry.id),
      title: entry.name,
      meta: 'v${entry.version}$author',
      trailing: trailing,
      onTap: () => _onCatalogTap(entry),
    );
  }

  Widget _communityTile(InstalledExtension ext) {
    return _ExtensionTile(
      letter: _initial(ext.manifest.name),
      color: _catalogColor(ext.manifest.id),
      title: ext.manifest.name,
      meta: 'v${ext.manifest.version} · Installed',
      trailing: PopupMenuButton<String>(
        tooltip: 'Extension actions',
        icon: const Icon(Icons.more_vert, size: 20),
        onSelected: (_) => _removeExtension(ext),
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'remove', child: Text('Remove')),
        ],
      ),
    );
  }

  String _initial(String name) {
    final trimmed = name.trim();
    return trimmed.isEmpty ? '?' : trimmed[0].toUpperCase();
  }

  Color _catalogColor(String id) {
    const palette = [
      Color(0xFF3B7EA1),
      Color(0xFFC25E00),
      Color(0xFF4A7FC1),
      Color(0xFF00897B),
      Color(0xFF8E24AA),
      Color(0xFFE53935),
      Color(0xFF1E88E5),
      Color(0xFF6B7B8C),
    ];
    var hash = 0;
    for (final unit in id.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return palette[hash % palette.length];
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final int count;
  final bool expanded;
  final VoidCallback onTap;

  const _SectionHeader({
    required this.title,
    required this.count,
    required this.expanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 16, 6),
        child: Row(
          children: [
            AnimatedRotation(
              turns: expanded ? 0.25 : 0,
              duration: const Duration(milliseconds: 160),
              child: Icon(
                Icons.chevron_right_rounded,
                size: 22,
                color: muted,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              title,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 8),
            Text(
              '$count',
              style: TextStyle(fontSize: 12, color: muted),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExtensionTile extends StatelessWidget {
  final IconData? icon;
  final String? letter;
  final Color color;
  final String title;
  final String meta;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _ExtensionTile({
    this.icon,
    this.letter,
    required this.color,
    required this.title,
    required this.meta,
    this.trailing,
    this.onTap,
  }) : assert(icon != null || letter != null);

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      horizontalTitleGap: 14,
      leading: Container(
        width: 42,
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(11),
        ),
        child: icon != null
            ? Icon(icon, size: 22, color: color)
            : Text(
                letter!,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
      ),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        meta,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12, color: muted),
      ),
      trailing: trailing,
      onTap: onTap,
    );
  }
}

class _EmptyLine extends StatelessWidget {
  final String text;

  const _EmptyLine(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Text(text, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}

class _EmptySearchState extends StatelessWidget {
  final String query;

  const _EmptySearchState({required this.query});

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_off_rounded, size: 36, color: muted),
          const SizedBox(height: 8),
          Text(
            'No extensions found for "$query"',
            style: TextStyle(fontSize: 13, color: muted),
          ),
        ],
      ),
    );
  }
}
