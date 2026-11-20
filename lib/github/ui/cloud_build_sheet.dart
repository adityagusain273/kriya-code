import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/di.dart';
import '../../core/result.dart';
import '../../editor/templates/ci_templates.dart';
import '../../workspace/fs_service.dart';
import '../api_client.dart';
import '../artifact_installer.dart';
import '../models.dart';

/// Cloud build panel: trigger a GitHub Actions workflow, watch it, install the
/// APK it produces.
///
/// The build itself runs on GitHub's runners — a phone cannot compile an APK
/// without being killed for memory — so everything here is scheduling and
/// polling the API.
class CloudBuildSheet extends StatefulWidget {
  final String token;
  final String owner;
  final String repo;
  final String? defaultBranch;

  /// Workspace copy of the repository, used for the 1-tap workflow scaffold.
  final String? localDir;

  const CloudBuildSheet({
    super.key,
    required this.token,
    required this.owner,
    required this.repo,
    this.defaultBranch,
    this.localDir,
  });

  static Future<void> show(
    BuildContext context, {
    required String token,
    required String owner,
    required String repo,
    String? defaultBranch,
    String? localDir,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => CloudBuildSheet(
        token: token,
        owner: owner,
        repo: repo,
        defaultBranch: defaultBranch,
        localDir: localDir,
      ),
    );
  }

  /// Asks which repository to build, then opens the sheet for it.
  static Future<void> pickRepo(BuildContext context, {required String token}) async {
    final repo = await showModalBottomSheet<GHRepo>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _RepoPicker(token: token),
    );
    if (repo == null || !context.mounted) return;
    final parts = repo.fullName.split('/');
    if (parts.length != 2) return;
    await show(
      context,
      token: token,
      owner: parts.first,
      repo: parts.last,
      defaultBranch: repo.defaultBranch,
    );
  }

  @override
  State<CloudBuildSheet> createState() => _CloudBuildSheetState();
}

class _CloudBuildSheetState extends State<CloudBuildSheet> {
  final _api = sl<GitHubApiClient>();

  List<GHWorkflow> _workflows = const [];
  List<GHBranch> _branches = const [];
  List<GHJobSummary> _jobs = const [];
  List<GHArtifact> _artifacts = const [];

  String? _branch;
  GHWorkflow? _workflow;
  GHWorkflowRun? _run;

  bool _loading = true;
  bool _busy = false;
  bool _disposed = false;
  bool _refreshing = false;

  /// Set when this sheet dispatched a run, so polling does not adopt an older
  /// run on the same branch and show its artifacts as if they were new.
  DateTime? _requestedAt;
  int? _downloading;
  String? _message;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _disposed = true;
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _message = null;
      _requestedAt = null;
    });
    final workflows = await _api.listWorkflows(
      widget.token,
      owner: widget.owner,
      repo: widget.repo,
    );
    final branches = await _api.listBranches(widget.token, '${widget.owner}/${widget.repo}');
    if (_disposed) return;

    setState(() {
      _loading = false;
      workflows.fold(
        (value) => _workflows = value,
        (error) => _message = error,
      );
      branches.fold(
        (value) => _branches = value,
        (error) => _message ??= error,
      );

      if (_workflows.isNotEmpty) {
        _workflow = _workflows.firstWhere(
          (w) => w.path.endsWith('build-apk.yml'),
          orElse: () => _workflows.first,
        );
      }
      final wanted = widget.defaultBranch;
      final names = _branches.map((b) => b.name).toList();
      _branch = names.contains(wanted) ? wanted : (names.isEmpty ? null : names.first);
    });

    // Reopening the sheet while a build is running should pick it up.
    await _refreshRun();
  }

  Future<void> _trigger() async {
    final workflow = _workflow;
    final branch = _branch;
    if (workflow == null || branch == null) return;

    setState(() {
      _busy = true;
      _message = 'Requesting build on $branch…';
      _run = null;
      _jobs = const [];
      _artifacts = const [];
      _requestedAt = DateTime.now();
    });

    final result = await _api.dispatchWorkflow(
      widget.token,
      owner: widget.owner,
      repo: widget.repo,
      workflowId: '${workflow.id}',
      ref: branch,
    );
    if (_disposed) return;

    result.fold(
      (_) {
        setState(() => _message = 'Build queued. GitHub needs a few seconds to list the run.');
        _startPolling();
      },
      (error) {
        setState(() {
          _busy = false;
          _requestedAt = null;
          _message = error;
        });
      },
    );
  }

  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 10), (_) => _refreshRun());
  }

  Future<void> _refreshRun() async {
    if (_refreshing || _disposed) return;
    _refreshing = true;
    try {
      await _refreshRunOnce();
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _refreshRunOnce() async {
    final workflow = _workflow;
    if (workflow == null || _disposed) return;

    final runs = await _api.listWorkflowRuns(
      widget.token,
      owner: widget.owner,
      repo: widget.repo,
      workflowId: '${workflow.id}',
    );
    if (_disposed) return;
    if (!runs.isOk) {
      setState(() => _message = runs.errorOrNull);
      return;
    }

    var candidates = runs.valueOrNull ?? const <GHWorkflowRun>[];
    final requestedAt = _requestedAt;
    if (requestedAt != null) {
      // API clocks and the phone clock do not agree to the second.
      final cutoff = requestedAt.subtract(const Duration(seconds: 5));
      candidates = candidates.where((run) => run.createdAt.isAfter(cutoff)).toList();
    }

    if (candidates.isEmpty) {
      if (requestedAt != null) {
        setState(() => _message = 'Waiting for GitHub to start the run…');
      }
      return;
    }
    final latest = candidates.first;

    final changed = _run?.id != latest.id;
    setState(() {
      _run = latest;
      _busy = latest.status != 'completed';
      _message = null;
    });

    if (latest.isFinished && latest.isSuccess && (changed || _artifacts.isEmpty)) {
      final artifacts = await _api.listRunArtifacts(
        widget.token,
        owner: widget.owner,
        repo: widget.repo,
        runId: latest.id,
      );
      if (_disposed) return;
      artifacts.fold(
        (value) => setState(() => _artifacts = value),
        (error) => setState(() => _message = error),
      );
    }

    if (latest.status != 'completed') {
      if (_poll == null) _startPolling();
    } else {
      _poll?.cancel();
      _poll = null;
      _requestedAt = null;
    }

    // Steps are the only progress signal inside a running job.
    final jobs = await _api.listRunJobs(
      widget.token,
      owner: widget.owner,
      repo: widget.repo,
      runId: latest.id,
    );
    if (_disposed) return;
    jobs.fold(
      (value) => setState(() => _jobs = value),
      (error) => setState(() => _message = error),
    );
  }

  Future<void> _download(GHArtifact artifact) async {
    setState(() {
      _downloading = artifact.id;
      _message = 'Downloading ${artifact.name}…';
    });
    final result = await _api.downloadArtifact(
      widget.token,
      owner: widget.owner,
      repo: widget.repo,
      artifactId: artifact.id,
    );
    if (_disposed) return;

    final bytes = result.valueOrNull;
    if (bytes == null) {
      setState(() {
        _downloading = null;
        _message = result.errorOrNull;
      });
      return;
    }

    try {
      final apk = await ArtifactInstaller.prepareApk(bytes, artifactId: artifact.id);
      if (_disposed) return;
      if (apk == null) {
        setState(() {
          _downloading = null;
          _message = '${artifact.name} does not contain an APK.';
        });
        return;
      }
      final opened = await ArtifactInstaller.install(apk);
      if (_disposed) return;
      setState(() {
        _downloading = null;
        _message = opened
            ? 'Installer opened for ${p.basename(apk.path)}.'
            : 'Android refused the installer. Allow "install unknown apps" for Kriya.';
      });
    } catch (e) {
      if (_disposed) return;
      setState(() {
        _downloading = null;
        _message = 'Could not unpack the artifact: $e';
      });
    }
  }

  Future<void> _scaffoldWorkflow() async {
    final dir = widget.localDir;
    if (dir == null) {
      setState(() => _message = 'Clone this repository first, then add the workflow.');
      return;
    }
    try {
      final created = await CiTemplates.ensureBuildWorkflow(sl<FsService>(), dir);
      if (_disposed) return;
      setState(() {
        _message = created
            ? 'Added .github/workflows/build-apk.yml. Commit and push it, then refresh.'
            : 'This repository already has .github/workflows/build-apk.yml.';
      });
    } catch (e) {
      if (_disposed) return;
      setState(() => _message = 'Could not write the workflow: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final run = _run;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: _loading
              ? const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                )
              : ListView(
                  shrinkWrap: true,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.cloud_upload_outlined, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Cloud Build — ${widget.owner}/${widget.repo}',
                            style: theme.textTheme.titleSmall,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.refresh, size: 18),
                          tooltip: 'Reload workflows',
                          onPressed: _busy ? null : _load,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_workflows.isEmpty)
                      _noWorkflows(theme)
                    else ...[
                      DropdownButtonFormField<int>(
                        initialValue: _workflow?.id,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Workflow',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        items: _workflows
                            .map((w) => DropdownMenuItem(
                                  value: w.id,
                                  child: Text(w.name, overflow: TextOverflow.ellipsis),
                                ))
                            .toList(),
                        onChanged: _busy
                            ? null
                            : (id) => setState(() {
                                  _workflow = _workflows.firstWhere((w) => w.id == id);
                                }),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _branch,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Branch',
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                              items: _branches
                                  .map((b) => DropdownMenuItem(
                                        value: b.name,
                                        child: Text(b.name, overflow: TextOverflow.ellipsis),
                                      ))
                                  .toList(),
                              onChanged: _busy
                                  ? null
                                  : (value) => setState(() => _branch = value),
                            ),
                          ),
                          const SizedBox(width: 12),
                          FilledButton.icon(
                            icon: _busy
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.play_arrow, size: 18),
                            label: const Text('Trigger Build'),
                            onPressed: _busy || _branch == null ? null : _trigger,
                          ),
                        ],
                      ),
                      if (widget.localDir != null &&
                          !_workflows.any((w) => w.path.endsWith('build-apk.yml')))
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('Add build-apk.yml to workspace'),
                            onPressed: _busy ? null : _scaffoldWorkflow,
                          ),
                        ),
                    ],
                    if (run != null) ...[
                      const SizedBox(height: 16),
                      _RunStatus(run: run),
                      if (_jobs.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _steps(theme),
                      ],
                      if (_artifacts.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text('Artifacts', style: theme.textTheme.labelLarge),
                        for (final artifact in _artifacts)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.archive_outlined),
                            title: Text(artifact.name),
                            subtitle: Text(
                              '${(artifact.sizeInBytes / (1024 * 1024)).toStringAsFixed(1)} MB'
                              '${artifact.expired ? ' — expired' : ''}',
                            ),
                            trailing: _downloading == artifact.id
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : IconButton(
                                    icon: const Icon(Icons.install_mobile_outlined),
                                    tooltip: 'Download and install',
                                    onPressed: artifact.expired ||
                                            _downloading != null
                                        ? null
                                        : () => _download(artifact),
                                  ),
                          ),
                      ],
                    ],
                    if (_message != null) ...[
                      const SizedBox(height: 12),
                      Text(_message!, style: theme.textTheme.bodySmall),
                    ],
                  ],
                ),
        ),
      ),
    );
  }

  Widget _noWorkflows(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'No GitHub Actions workflow found in this repository. '
          'Cloud builds need one to know what to compile.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        if (widget.localDir != null)
          OutlinedButton.icon(
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add build-apk.yml to workspace'),
            onPressed: _scaffoldWorkflow,
          ),
      ],
    );
  }

  Widget _steps(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Steps', style: theme.textTheme.labelLarge),
        for (final job in _jobs) ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  job.name,
                  style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton.icon(
                icon: const Icon(Icons.receipt_long_outlined, size: 14),
                label: const Text('Logs', style: TextStyle(fontSize: 11)),
                onPressed: () => _showLogs(job),
              ),
            ],
          ),
          for (final step in job.steps)
            Padding(
              padding: const EdgeInsets.only(left: 8, top: 2, bottom: 2),
              child: Row(
                children: [
                  Icon(_stepIcon(step.status, step.conclusion), size: 14),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      step.name,
                      style: theme.textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    step.conclusion.isEmpty ? step.status : step.conclusion,
                    style: theme.textTheme.labelSmall,
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }

  Future<void> _showLogs(GHJobSummary job) async {
    final result = await _api.jobLogs(
      widget.token,
      owner: widget.owner,
      repo: widget.repo,
      jobId: job.id,
    );
    if (!mounted) return;
    final text = result.valueOrNull;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: text == null
                ? Text(result.errorOrNull ?? 'No logs available.')
                : SingleChildScrollView(
                    reverse: true,
                    child: SelectableText(
                      text,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  static IconData _stepIcon(String status, String conclusion) {
    if (status != 'completed') return Icons.pending_outlined;
    switch (conclusion) {
      case 'success':
        return Icons.check_circle_outline;
      case 'skipped':
        return Icons.remove_circle_outline;
      default:
        return Icons.error_outline;
    }
  }
}

class _RunStatus extends StatelessWidget {
  final GHWorkflowRun run;

  const _RunStatus({required this.run});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, color, label) = switch (run) {
      _ when run.isSuccess => (Icons.check_circle, Colors.green, 'Success'),
      _ when run.isFinished => (Icons.cancel, Colors.redAccent, run.conclusion),
      _ when run.status == 'in_progress' => (
          Icons.sync,
          Colors.orange,
          'Running',
        ),
      _ => (Icons.schedule, Colors.blueGrey, run.status),
    };
    final duration = run.duration;

    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Run #${run.id} · ${run.headBranch} · $label',
            style: theme.textTheme.bodyMedium,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (duration != null)
          Text(
            '${duration.inMinutes}m ${duration.inSeconds % 60}s',
            style: theme.textTheme.labelSmall,
          ),
      ],
    );
  }
}

/// Repository list for the command palette, which has no repo in hand.
class _RepoPicker extends StatefulWidget {
  final String token;

  const _RepoPicker({required this.token});

  @override
  State<_RepoPicker> createState() => _RepoPickerState();
}

class _RepoPickerState extends State<_RepoPicker> {
  late final Future<Result<List<GHRepo>>> _repos =
      sl<GitHubApiClient>().listRepos(widget.token);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
        child: FutureBuilder<Result<List<GHRepo>>>(
          future: _repos,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final repos = snapshot.data!.valueOrNull;
            if (repos == null) {
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Text(snapshot.data!.errorOrNull ?? 'Could not load repositories.'),
              );
            }
            return ListView.builder(
              shrinkWrap: true,
              itemCount: repos.length,
              itemBuilder: (context, i) => ListTile(
                leading: Icon(repos[i].isPrivate ? Icons.lock_outline : Icons.public),
                title: Text(repos[i].fullName),
                subtitle: Text(
                  repos[i].description.isEmpty ? '(no description)' : repos[i].description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => Navigator.pop(context, repos[i]),
              ),
            );
          },
        ),
      ),
    );
  }
}
