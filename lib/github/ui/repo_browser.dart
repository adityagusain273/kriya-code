import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/di.dart';
import '../../workspace/fs_service.dart';
import '../api_client.dart';
import '../models.dart';
import 'repo_actions.dart';
import 'repo_browser_model.dart';

enum RepoFilter { all, cloned, public, private }

class RepoBrowser extends StatefulWidget {
  final String token;
  final Future<void> Function() onSignOut;

  const RepoBrowser({super.key, required this.token, required this.onSignOut});

  @override
  State<RepoBrowser> createState() => _RepoBrowserState();
}

class _RepoBrowserState extends State<RepoBrowser> {
  String _query = '';
  RepoFilter _filter = RepoFilter.all;
  final _searchController = TextEditingController();

  static final RegExp _repoNameChars = RegExp(r'[^A-Za-z0-9._\-/]');

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _isCloned(String fullName) {
    try {
      final safeName = fullName.replaceAll(_repoNameChars, '_');
      return sl<FsService>().exists('repos/$safeName/.git');
    } catch (_) {
      return false;
    }
  }

  List<GHRepo> _filterList(List<GHRepo> all) {
    return all.where((repo) {
      if (_filter == RepoFilter.cloned && !_isCloned(repo.fullName)) {
        return false;
      }
      if (_filter == RepoFilter.private && !repo.isPrivate) {
        return false;
      }
      if (_filter == RepoFilter.public && repo.isPrivate) {
        return false;
      }
      if (_query.isNotEmpty) {
        final q = _query.toLowerCase();
        final matchesName = repo.name.toLowerCase().contains(q) ||
            repo.fullName.toLowerCase().contains(q);
        final matchesDesc = repo.description.toLowerCase().contains(q);
        return matchesName || matchesDesc;
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ChangeNotifierProvider(
      create: (_) =>
          RepoBrowserModel(sl<GitHubApiClient>(), widget.token)..loadRepos(),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Your Repositories'),
          actions: [
            Consumer<RepoBrowserModel>(
              builder: (_, model, __) => IconButton(
                icon: const Icon(Icons.refresh_rounded),
                tooltip: 'Refresh',
                onPressed: model.loading ? null : model.loadRepos,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.logout_rounded),
              tooltip: 'Sign out',
              onPressed: widget.onSignOut,
            ),
          ],
        ),
        body: Consumer<RepoBrowserModel>(
          builder: (context, model, _) {
            if (model.loading && model.repos.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }
            if (model.error != null && model.repos.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline_rounded,
                          size: 48, color: cs.error),
                      const SizedBox(height: 12),
                      Text(model.error!, textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: model.loadRepos,
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text('Try Again'),
                      ),
                    ],
                  ),
                ),
              );
            }

            final filtered = _filterList(model.repos);
            final clonedCount =
                model.repos.where((r) => _isCloned(r.fullName)).length;
            final publicCount = model.repos.where((r) => !r.isPrivate).length;
            final privateCount = model.repos.where((r) => r.isPrivate).length;

            return RefreshIndicator(
              onRefresh: model.loadRepos,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: TextField(
                      controller: _searchController,
                      onChanged: (val) => setState(() => _query = val.trim()),
                      decoration: InputDecoration(
                        hintText: 'Search repositories…',
                        prefixIcon: const Icon(Icons.search_rounded, size: 20),
                        suffixIcon: _query.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded, size: 18),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _query = '');
                                },
                              )
                            : null,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        filled: true,
                        fillColor: cs.surfaceContainerHigh,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(
                            color: cs.outlineVariant.withValues(alpha: 0.3),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(
                            color: cs.outlineVariant.withValues(alpha: 0.3),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: cs.primary, width: 1.5),
                        ),
                      ),
                    ),
                  ),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 4),
                    child: Row(
                      children: [
                        _FilterChip(
                          label: 'All (${model.repos.length})',
                          selected: _filter == RepoFilter.all,
                          onSelected: () =>
                              setState(() => _filter = RepoFilter.all),
                        ),
                        const SizedBox(width: 8),
                        _FilterChip(
                          label: 'Cloned ($clonedCount)',
                          selected: _filter == RepoFilter.cloned,
                          onSelected: () =>
                              setState(() => _filter = RepoFilter.cloned),
                        ),
                        const SizedBox(width: 8),
                        _FilterChip(
                          label: 'Public ($publicCount)',
                          selected: _filter == RepoFilter.public,
                          onSelected: () =>
                              setState(() => _filter = RepoFilter.public),
                        ),
                        const SizedBox(width: 8),
                        _FilterChip(
                          label: 'Private ($privateCount)',
                          selected: _filter == RepoFilter.private,
                          onSelected: () =>
                              setState(() => _filter = RepoFilter.private),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Expanded(
                    child: filtered.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(32),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.inventory_2_outlined,
                                      size: 48,
                                      color: cs.onSurfaceVariant
                                          .withValues(alpha: 0.5)),
                                  const SizedBox(height: 12),
                                  Text(
                                    _query.isNotEmpty
                                        ? 'No repositories matching "$_query"'
                                        : 'No repositories found in this filter',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: cs.onSurfaceVariant,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : LayoutBuilder(
                            builder: (context, constraints) {
                              if (constraints.maxWidth > 650) {
                                return GridView.builder(
                                  padding: const EdgeInsets.all(16),
                                  gridDelegate:
                                      const SliverGridDelegateWithMaxCrossAxisExtent(
                                    maxCrossAxisExtent: 460,
                                    mainAxisExtent: 150,
                                    crossAxisSpacing: 12,
                                    mainAxisSpacing: 12,
                                  ),
                                  itemCount: filtered.length,
                                  itemBuilder: (context, i) {
                                    final repo = filtered[i];
                                    return _RepoCard(
                                      repo: repo,
                                      token: widget.token,
                                      isCloned: _isCloned(repo.fullName),
                                    );
                                  },
                                );
                              }
                              return ListView.separated(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 8),
                                itemCount: filtered.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 10),
                                itemBuilder: (context, i) {
                                  final repo = filtered[i];
                                  return _RepoCard(
                                    repo: repo,
                                    token: widget.token,
                                    isCloned: _isCloned(repo.fullName),
                                  );
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onSelected;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
        color: selected ? cs.onPrimaryContainer : cs.onSurfaceVariant,
      ),
      backgroundColor: cs.surfaceContainerHigh,
      selectedColor: cs.primaryContainer,
      checkmarkColor: cs.onPrimaryContainer,
      side: BorderSide(
        color: selected
            ? cs.primary.withValues(alpha: 0.5)
            : cs.outlineVariant.withValues(alpha: 0.3),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _RepoCard extends StatelessWidget {
  final GHRepo repo;
  final String token;
  final bool isCloned;

  const _RepoCard({
    required this.repo,
    required this.token,
    required this.isCloned,
  });

  Color _languageColor(String? language) {
    switch (language?.toLowerCase()) {
      case 'dart':
        return const Color(0xFF00B4AB);
      case 'javascript':
        return const Color(0xFFF7DF1E);
      case 'typescript':
        return const Color(0xFF3178C6);
      case 'python':
        return const Color(0xFF3572A5);
      case 'c++':
      case 'cpp':
        return const Color(0xFFF34B7D);
      case 'c':
        return const Color(0xFF555555);
      case 'java':
        return const Color(0xFFB07219);
      case 'kotlin':
        return const Color(0xFFA97BFF);
      case 'rust':
        return const Color(0xFFDEA584);
      case 'html':
        return const Color(0xFFE34C26);
      case 'css':
        return const Color(0xFF563D7C);
      default:
        return const Color(0xFF4FC3F7);
    }
  }

  String _formatRelativeDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) {
      if (diff.inHours == 0) return 'Just now';
      return '${diff.inHours}h ago';
    }
    if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    }
    if (diff.inDays < 30) {
      final weeks = (diff.inDays / 7).floor();
      return '${weeks}w ago';
    }
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Material(
      color: cs.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isCloned
              ? cs.primary.withValues(alpha: 0.4)
              : cs.outlineVariant.withValues(alpha: 0.28),
          width: isCloned ? 1.2 : 1.0,
        ),
      ),
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => RepoActionsPage(repo: repo, token: token),
          ),
        ),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: (repo.isPrivate ? cs.error : cs.primary)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      repo.isPrivate
                          ? Icons.lock_outline_rounded
                          : Icons.public_rounded,
                      size: 18,
                      color: repo.isPrivate ? cs.error : cs.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          repo.name,
                          style: text.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                            fontSize: 15,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (repo.owner.isNotEmpty)
                          Text(
                            repo.owner,
                            style: text.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                              fontSize: 11,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  if (isCloned)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: cs.primary.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.folder_rounded,
                              size: 12, color: cs.primary),
                          const SizedBox(width: 4),
                          Text(
                            'Cloned',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: cs.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              if (repo.description.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  repo.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    height: 1.35,
                    fontSize: 12,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.fork_right_rounded,
                            size: 13, color: cs.onSurfaceVariant),
                        const SizedBox(width: 3),
                        Text(
                          repo.defaultBranch,
                          style: TextStyle(
                            fontSize: 11,
                            color: cs.onSurfaceVariant,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (repo.language != null) ...[
                    const SizedBox(width: 10),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: _languageColor(repo.language),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          repo.language!,
                          style: TextStyle(
                            fontSize: 11,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (repo.stargazersCount > 0) ...[
                    const SizedBox(width: 10),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.star_rounded,
                            size: 13, color: Colors.amber[600]),
                        const SizedBox(width: 2),
                        Text(
                          '${repo.stargazersCount}',
                          style: TextStyle(
                            fontSize: 11,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const Spacer(),
                  Text(
                    _formatRelativeDate(repo.updatedAt),
                    style: TextStyle(
                      fontSize: 11,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
