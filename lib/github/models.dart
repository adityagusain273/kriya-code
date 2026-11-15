class GHUser {
  final String login;
  final String name;
  final String avatarUrl;

  const GHUser({required this.login, required this.name, required this.avatarUrl});

  factory GHUser.fromJson(Map<String, Object?> j) => GHUser(
        login: j['login'] as String? ?? '',
        name: (j['name'] as String?) ?? j['login'] as String? ?? '',
        avatarUrl: j['avatar_url'] as String? ?? '',
      );
}

class GHRepo {
  final String fullName;
  final String description;
  final bool isPrivate;
  final String defaultBranch;
  final DateTime updatedAt;
  final String? language;
  final int stargazersCount;
  final int forksCount;
  final bool isFork;

  const GHRepo({
    required this.fullName,
    required this.description,
    required this.isPrivate,
    required this.defaultBranch,
    required this.updatedAt,
    this.language,
    this.stargazersCount = 0,
    this.forksCount = 0,
    this.isFork = false,
  });

  String get name {
    final parts = fullName.split('/');
    return parts.length > 1 ? parts[1] : fullName;
  }

  String get owner {
    final parts = fullName.split('/');
    return parts.isNotEmpty ? parts[0] : '';
  }

  factory GHRepo.fromJson(Map<String, Object?> j) => GHRepo(
        fullName: j['full_name'] as String? ?? '',
        description: (j['description'] as String?) ?? '',
        isPrivate: j['private'] == true,
        defaultBranch: (j['default_branch'] as String?) ?? 'main',
        updatedAt: DateTime.tryParse(j['updated_at'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        language: j['language'] as String?,
        stargazersCount: (j['stargazers_count'] as num?)?.toInt() ?? 0,
        forksCount: (j['forks_count'] as num?)?.toInt() ?? 0,
        isFork: j['fork'] == true,
      );
}

class GHBranch {
  final String name;

  const GHBranch(this.name);

  factory GHBranch.fromJson(Map<String, Object?> j) =>
      GHBranch((j['name'] as String?) ?? '');
}

class GHCommit {
  final String sha;
  final String message;
  final String author;
  final DateTime date;

  const GHCommit({
    required this.sha,
    required this.message,
    required this.author,
    required this.date,
  });

  factory GHCommit.fromJson(Map<String, Object?> j) {
    final commit = j['commit'] as Map<String, Object?>? ?? {};
    return GHCommit(
      sha: j['sha'] as String? ?? '',
      message: (commit['message'] as String?) ?? '',
      author: ((commit['author'] as Map<String, Object?>?)?['name'] as String?) ?? 'unknown',
      date: DateTime.tryParse(
              (commit['author'] as Map<String, Object?>?)?['date'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

class GHWorkflow {
  final int id;
  final String name;
  final String path;
  final String state;

  const GHWorkflow({
    required this.id,
    required this.name,
    required this.path,
    required this.state,
  });

  factory GHWorkflow.fromJson(Map<String, Object?> j) => GHWorkflow(
        id: (j['id'] as num?)?.toInt() ?? 0,
        name: j['name'] as String? ?? '',
        path: j['path'] as String? ?? '',
        state: j['state'] as String? ?? '',
      );
}

class GHWorkflowRun {
  final int id;
  final String name;
  final String status;
  final String conclusion;
  final String headBranch;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const GHWorkflowRun({
    required this.id,
    required this.name,
    required this.status,
    required this.conclusion,
    required this.headBranch,
    required this.createdAt,
    this.updatedAt,
  });

  bool get isFinished => status == 'completed';
  bool get isSuccess => isFinished && conclusion == 'success';

  Duration? get duration {
    final end = updatedAt;
    if (end == null || !isFinished) return null;
    final d = end.difference(createdAt);
    return d.isNegative ? Duration.zero : d;
  }

  factory GHWorkflowRun.fromJson(Map<String, Object?> j) => GHWorkflowRun(
        id: (j['id'] as num?)?.toInt() ?? 0,
        name: j['name'] as String? ?? '',
        status: j['status'] as String? ?? '',
        conclusion: j['conclusion'] as String? ?? '',
        headBranch: j['head_branch'] as String? ?? '',
        createdAt: DateTime.tryParse(j['created_at'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        updatedAt: DateTime.tryParse(j['updated_at'] as String? ?? ''),
      );
}

class GHArtifact {
  final int id;
  final String name;
  final int sizeInBytes;
  final bool expired;

  const GHArtifact({
    required this.id,
    required this.name,
    required this.sizeInBytes,
    required this.expired,
  });

  factory GHArtifact.fromJson(Map<String, Object?> j) => GHArtifact(
        id: (j['id'] as num?)?.toInt() ?? 0,
        name: j['name'] as String? ?? '',
        sizeInBytes: (j['size_in_bytes'] as num?)?.toInt() ?? 0,
        expired: j['expired'] == true,
      );
}

class GHJobSummary {
  final int id;
  final String name;
  final String status;
  final String conclusion;
  final List<GHStepSummary> steps;

  const GHJobSummary({
    required this.id,
    required this.name,
    required this.status,
    required this.conclusion,
    required this.steps,
  });

  factory GHJobSummary.fromJson(Map<String, Object?> j) => GHJobSummary(
        id: (j['id'] as num?)?.toInt() ?? 0,
        name: j['name'] as String? ?? '',
        status: j['status'] as String? ?? '',
        conclusion: j['conclusion'] as String? ?? '',
        steps: (j['steps'] as List<Object?>? ?? const [])
            .whereType<Map<String, Object?>>()
            .map(GHStepSummary.fromJson)
            .toList(),
      );
}

class GHStepSummary {
  final String name;
  final String status;
  final String conclusion;

  const GHStepSummary({
    required this.name,
    required this.status,
    required this.conclusion,
  });

  factory GHStepSummary.fromJson(Map<String, Object?> j) => GHStepSummary(
        name: j['name'] as String? ?? '',
        status: j['status'] as String? ?? '',
        conclusion: j['conclusion'] as String? ?? '',
      );
}

class GitDiffEntry {
  final String path;
  final bool isNew;
  final bool isDeleted;
  final String patch;

  const GitDiffEntry({
    required this.path,
    required this.isNew,
    required this.isDeleted,
    required this.patch,
  });
}
