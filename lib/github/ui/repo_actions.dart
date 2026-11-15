import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/di.dart';
import '../../workspace/fs_service.dart';
import '../api_client.dart';
import '../git_service.dart';
import '../models.dart';
import 'cloud_build_sheet.dart';
import 'commit_list.dart';
import 'git_workspace_page.dart';

class RepoActionsPage extends StatefulWidget {
  final GHRepo repo;
  final String token;

  const RepoActionsPage({super.key, required this.repo, required this.token});

  @override
  State<RepoActionsPage> createState() => _RepoActionsPageState();
}

class _RepoActionsPageState extends State<RepoActionsPage> {
  bool _busy = false;
  String? _message;

  static final RegExp _repoNameChars = RegExp(r'[^A-Za-z0-9._\-/]');

  String get _safeFullName =>
      widget.repo.fullName.replaceAll(_repoNameChars, '_');

  String get _cloneDir {
    final root = sl<FsService>().rootPath;
    return '$root/repos/$_safeFullName';
  }

  String get _relativeCloneDir => 'repos/$_safeFullName';

  bool get _alreadyCloned {
    try {
      return sl<FsService>().exists('repos/$_safeFullName/.git');
    } catch (_) {
      return false;
    }
  }

  String get _owner => widget.repo.owner;

  String get _repoName => widget.repo.name;

  void _openCloudBuild() {
    CloudBuildSheet.show(
      context,
      token: widget.token,
      owner: _owner,
      repo: _repoName,
      defaultBranch: widget.repo.defaultBranch,
      localDir: _alreadyCloned ? _cloneDir : null,
    );
  }

  Future<void> _openOnGitHub() async {
    final url = Uri.parse('https://github.com/${widget.repo.fullName}');
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  Future<void> _clone() async {
    setState(() {
      _busy = true;
      _message = 'Cloning ${widget.repo.fullName}…';
    });
    try {
      await sl<FsService>().createDirectory('repos');
      final result = await sl<GitService>().clone(
        httpsUrl: 'https://github.com/${widget.repo.fullName}.git',
        token: widget.token,
        destinationPath: _cloneDir,
      );
      if (!mounted) return;
      setState(
          () => _message = result.fold((_) => 'Cloned successfully', (e) => e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openWorkspace() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GitWorkspacePage(
          repoDir: _cloneDir,
          token: widget.token,
          defaultBranch: widget.repo.defaultBranch,
        ),
      ),
    );
  }

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

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final repo = widget.repo;
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final isCloned = _alreadyCloned;

    return Scaffold(
      appBar: AppBar(
        title: Text(repo.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_browser_rounded),
            tooltip: 'Open on GitHub',
            onPressed: _openOnGitHub,
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: cs.outlineVariant.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: (repo.isPrivate ? cs.error : cs.primary)
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: (repo.isPrivate ? cs.error : cs.primary)
                                    .withValues(alpha: 0.25),
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Icon(
                              repo.isPrivate
                                  ? Icons.lock_outline_rounded
                                  : Icons.public_rounded,
                              size: 22,
                              color: repo.isPrivate ? cs.error : cs.primary,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  repo.name,
                                  style: text.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.3,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  repo.fullName,
                                  style: text.bodySmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        repo.description.isNotEmpty
                            ? repo.description
                            : 'No description provided.',
                        style: text.bodyMedium?.copyWith(
                          color: repo.description.isNotEmpty
                              ? cs.onSurface
                              : cs.onSurfaceVariant.withValues(alpha: 0.7),
                          fontStyle: repo.description.isNotEmpty
                              ? FontStyle.normal
                              : FontStyle.italic,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: cs.outlineVariant.withValues(alpha: 0.2),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.fork_right_rounded,
                                    size: 13, color: cs.onSurfaceVariant),
                                const SizedBox(width: 4),
                                Text(
                                  'default: ${repo.defaultBranch}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: cs.onSurfaceVariant,
                                    fontFamily: 'monospace',
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: cs.outlineVariant.withValues(alpha: 0.2),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  repo.isPrivate
                                      ? Icons.lock_outline_rounded
                                      : Icons.public_rounded,
                                  size: 12,
                                  color: cs.onSurfaceVariant,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  repo.isPrivate ? 'Private' : 'Public',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: cs.onSurfaceVariant,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (repo.language != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: cs.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color:
                                      cs.outlineVariant.withValues(alpha: 0.2),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 7,
                                    height: 7,
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
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: cs.outlineVariant.withValues(alpha: 0.2),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.schedule_rounded,
                                    size: 12, color: cs.onSurfaceVariant),
                                const SizedBox(width: 4),
                                Text(
                                  'Updated ${_formatDate(repo.updatedAt)}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: cs.onSurfaceVariant,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isCloned
                        ? cs.primary.withValues(alpha: 0.08)
                        : cs.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: isCloned
                          ? cs.primary.withValues(alpha: 0.35)
                          : cs.outlineVariant.withValues(alpha: 0.25),
                      width: isCloned ? 1.2 : 1.0,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(
                            isCloned
                                ? Icons.check_circle_rounded
                                : Icons.download_rounded,
                            size: 18,
                            color: isCloned ? cs.primary : cs.onSurfaceVariant,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            isCloned
                                ? 'Workspace Status: Cloned'
                                : 'Workspace Status: Not Cloned',
                            style: text.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: isCloned ? cs.primary : cs.onSurface,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        isCloned
                            ? 'Local path: $_relativeCloneDir'
                            : 'Will clone into: $_relativeCloneDir',
                        style: text.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontFamily: 'monospace',
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        height: 48,
                        child: FilledButton.icon(
                          icon: Icon(isCloned
                              ? Icons.folder_open_rounded
                              : Icons.download_rounded),
                          label: Text(
                            isCloned
                                ? 'Open Cloned Copy'
                                : 'Clone to Workspace',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          onPressed: _busy
                              ? null
                              : (isCloned ? _openWorkspace : _clone),
                          style: FilledButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Repository Tools',
                  style: text.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: cs.onSurfaceVariant,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 10),
                _ActionCard(
                  icon: Icons.cloud_upload_outlined,
                  title: 'Cloud Build / CI',
                  subtitle:
                      'Trigger GitHub Actions workflows and download built APKs',
                  onTap: _busy ? null : _openCloudBuild,
                ),
                const SizedBox(height: 10),
                _ActionCard(
                  icon: Icons.history_rounded,
                  title: 'View Commit History',
                  subtitle:
                      'Browse recent commits, author avatars, and commit diffs',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CommitListPage(
                        repo: repo.fullName,
                        token: widget.token,
                        client: sl<GitHubApiClient>(),
                      ),
                    ),
                  ),
                ),
                if (_busy) ...[
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: const LinearProgressIndicator(),
                  ),
                ],
                if (_message != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: _message!.contains('successfully')
                          ? cs.primary.withValues(alpha: 0.12)
                          : cs.errorContainer.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _message!.contains('successfully')
                            ? cs.primary.withValues(alpha: 0.3)
                            : cs.error.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _message!.contains('successfully')
                              ? Icons.check_circle_rounded
                              : Icons.info_outline_rounded,
                          size: 16,
                          color: _message!.contains('successfully')
                              ? cs.primary
                              : cs.error,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _message!,
                            style: text.bodySmall?.copyWith(
                              color: _message!.contains('successfully')
                                  ? cs.primary
                                  : cs.onErrorContainer,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Material(
      color: cs.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: cs.outlineVariant.withValues(alpha: 0.25),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 20, color: cs.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: text.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: text.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontSize: 11,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: cs.onSurfaceVariant.withValues(alpha: 0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
