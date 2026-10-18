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

  const GHRepo({
    required this.fullName,
    required this.description,
    required this.isPrivate,
    required this.defaultBranch,
    required this.updatedAt,
  });

  factory GHRepo.fromJson(Map<String, Object?> j) => GHRepo(
        fullName: j['full_name'] as String? ?? '',
        description: (j['description'] as String?) ?? '',
        isPrivate: j['private'] == true,
        defaultBranch: (j['default_branch'] as String?) ?? 'main',
        updatedAt: DateTime.tryParse(j['updated_at'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
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
