import 'package:flutter/material.dart';

import '../../core/di.dart';
import '../../execution/runtime_download_service.dart';
import '../../execution/ui/downloads_page.dart';
import '../../workspace/mdi.dart';
import '../host/extension_install_store.dart';

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
    id: 'bcode.lang.c_cpp',
    title: 'C / C++',
    subtitle: 'C and C++ language pack — highlighting, run support',
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

  final TextEditingController _searchController = TextEditingController();
  bool _searchVisible = false;
  String _query = '';

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

  Future<void> _onInstallTap(_ExtUi ext) async {
    final installed = _store.isInstalled(ext.id);
    if (installed) {
      setState(() => _store.uninstall(ext.id));
      final runtimeId = ext.runtimeId;
      if (runtimeId != null) await _downloads.remove(runtimeId);
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
              SnackBar(content: Text('Download failed: ${state.error ?? "unknown error"}')),
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

  @override
  Widget build(BuildContext context) {
    final results = _filtered;
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
        ],
      ),
      body: Column(
        children: [
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
            child: results.isEmpty
                ? _EmptySearchState(query: _query.trim())
                : ListView(
                    children: [
                      for (final ext in results)
                        _ExtensionCard(
                          ext: ext,
                          installed: _store.isInstalled(ext.id),
                          onTap: () => _onInstallTap(ext),
                          downloads: _downloads,
                        ),
                      if (_query.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text(
                            'Language packs include a downloadable runtime so you can keep '
                            'coding offline. Downloads are fetched from the Termux package '
                            'repository.',
                            style: TextStyle(fontSize: 12, color: Colors.white54),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
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
            query.isEmpty ? 'Type a name to search' : 'No extensions found for "$query"',
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
                          ? (progress != null ? '${(progress * 100).toInt()}%' : 'Downloading...')
                          : state.phase.name,
                      style: const TextStyle(fontSize: 10, color: Colors.white70),
                    ),
                    if (runtimeId != null) ...[
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: () => downloads.cancel(runtimeId),
                        child: Icon(Icons.cancel_rounded, size: 16, color: Colors.red.shade300),
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
