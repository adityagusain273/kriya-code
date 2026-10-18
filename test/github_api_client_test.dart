import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:b_code/github/api_client.dart';
import 'package:b_code/github/models.dart';

void main() {
  group('GitHubApiClient', () {
    test('getUser returns GHUser on success', () async {
      final client = http_testing.MockClient((_) async => http.Response(
            jsonEncode({
              'login': 'testuser',
              'name': 'Test User',
              'avatar_url': 'https://avatars.githubusercontent.com/u/1',
            }),
            200,
          ));

      final api = GitHubApiClient(client: client);
      final result = await api.getUser('ghp_test_token');

      expect(result.isOk, isTrue);
      final user = result.valueOrNull;
      expect(user?.login, 'testuser');
      expect(user?.name, 'Test User');
      expect(user?.avatarUrl, contains('avatars'));

      api.close();
    });

    test('getUser returns Err on 401', () async {
      final client = http_testing.MockClient((_) async => http.Response('unauthorized', 401));

      final api = GitHubApiClient(client: client);
      final result = await api.getUser('expired_token');

      expect(result.isOk, isFalse);
      expect(result.errorOrNull, contains('401'));

      api.close();
    });

    test('getUser returns Err on non-200', () async {
      final client = http_testing.MockClient((_) async => http.Response('not found', 404));

      final api = GitHubApiClient(client: client);
      final result = await api.getUser('token');

      expect(result.isOk, isFalse);
      expect(result.errorOrNull, contains('404'));

      api.close();
    });

    test('getUser sends correct headers', () async {
      final captured = <String, String>{};

      final client = http_testing.MockClient((request) async {
        captured.addAll(request.headers);
        return http.Response(
          jsonEncode({'login': 'u', 'name': 'n', 'avatar_url': ''}),
          200,
        );
      });

      final api = GitHubApiClient(client: client);
      await api.getUser('my-token-xyz');

      expect(captured['Authorization'], 'Bearer my-token-xyz');
      expect(captured['Accept'], 'application/vnd.github+json');
      expect(captured['X-GitHub-Api-Version'], '2022-11-28');

      api.close();
    });

    test('listRepos returns list of repos', () async {
      final client = http_testing.MockClient((_) async => http.Response(
            jsonEncode([
              {
                'full_name': 'user/repo1',
                'description': 'A repo',
                'private': false,
                'default_branch': 'main',
                'updated_at': '2026-01-01T00:00:00Z',
              },
              {
                'full_name': 'user/repo2',
                'description': null,
                'private': true,
                'default_branch': 'develop',
                'updated_at': '2026-02-01T00:00:00Z',
              },
            ]),
            200,
          ));

      final api = GitHubApiClient(client: client);
      final result = await api.listRepos('token');

      expect(result.isOk, isTrue);
      final repos = result.valueOrNull;
      expect(repos?.length, 2);
      expect(repos?.first.fullName, 'user/repo1');
      expect(repos?.last.isPrivate, isTrue);
      expect(repos?.last.defaultBranch, 'develop');

      api.close();
    });

    test('listBranches returns list of branches', () async {
      final client = http_testing.MockClient((_) async => http.Response(
            jsonEncode([
              {'name': 'main'},
              {'name': 'feature-branch'},
            ]),
            200,
          ));

      final api = GitHubApiClient(client: client);
      final result = await api.listBranches('token', 'user/repo');

      expect(result.isOk, isTrue);
      final branches = result.valueOrNull;
      expect(branches?.length, 2);
      expect(branches?.first.name, 'main');
      expect(branches?.last.name, 'feature-branch');

      api.close();
    });

    test('listCommits returns list of commits', () async {
      final client = http_testing.MockClient((_) async => http.Response(
            jsonEncode([
              {
                'sha': 'abc123',
                'commit': {
                  'message': 'Initial commit',
                  'author': {'name': 'Dev', 'date': '2026-01-01T00:00:00Z'},
                },
              },
            ]),
            200,
          ));

      final api = GitHubApiClient(client: client);
      final result = await api.listCommits('token', 'user/repo', 'main');

      expect(result.isOk, isTrue);
      final commits = result.valueOrNull;
      expect(commits?.length, 1);
      expect(commits?.first.sha, 'abc123');
      expect(commits?.first.message, 'Initial commit');
      expect(commits?.first.author, 'Dev');

      api.close();
    });

    test('handles network exception', () async {
      final client = http_testing.MockClient((_) async => throw Exception('network'));

      final api = GitHubApiClient(client: client);
      final result = await api.getUser('token');

      expect(result.isOk, isFalse);
      expect(result.errorOrNull, contains('network'));

      api.close();
    });
  });

  group('GitHub models', () {
    test('GHUser.fromJson handles missing fields', () {
      final user = GHUser.fromJson({});
      expect(user.login, '');
      expect(user.name, '');
      expect(user.avatarUrl, '');
    });

    test('GHRepo.fromJson handles missing fields', () {
      final repo = GHRepo.fromJson({});
      expect(repo.fullName, '');
      expect(repo.isPrivate, isFalse);
      expect(repo.defaultBranch, 'main');
    });

    test('GHCommit.fromJson handles missing fields', () {
      final commit = GHCommit.fromJson({});
      expect(commit.sha, '');
      expect(commit.message, '');
      expect(commit.author, 'unknown');
    });

    test('GHBranch.fromJson handles missing name', () {
      final branch = GHBranch.fromJson({});
      expect(branch.name, '');
    });
  });
}
