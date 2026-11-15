import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../core/constants.dart';
import '../core/pinned_http.dart';
import '../core/result.dart';
import 'models.dart';

class GitHubApiClient {
  static const _perPage = 50;

  final http.Client _client;

  /// Used only for the signed CDN leg of an artifact download, where a pinned
  /// host cannot be named in advance. Injectable so tests never touch the
  /// network.
  final http.Client _downloadClient;

  GitHubApiClient({http.Client? client, http.Client? downloadClient})
      : _client = client ?? PinnedHttpClient.create(),
        _downloadClient = downloadClient ?? http.Client();

  Map<String, String> _headers(String? token) => {
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Future<Result<T>> _get<T>(
    String path,
    T Function(List<Object?>) parse, {
    required String? token,
    Map<String, String>? query,
  }) async {
    try {
      final uri = Uri.parse('${AppConstants.githubApiBase}$path')
          .replace(queryParameters: {...?query, 'per_page': '$_perPage'});
      final response = await _client.get(uri, headers: _headers(token));
      if (response.statusCode == 401) return Err('Unauthorized — token expired. Re-login.');
      if (response.statusCode != 200) {
        return Err('GitHub API error ${response.statusCode}');
      }
      return Ok(parse(await decodeJsonBody(response) as List<Object?>));
    } catch (e) {
      return Err(_describe(e));
    }
  }

  Future<Result<GHUser>> getUser(String token) async {
    try {
      final response = await _client.get(
        Uri.parse('${AppConstants.githubApiBase}/user'),
        headers: _headers(token),
      );
      if (response.statusCode == 401) {
        return Err('Unauthorized (401) — token rejected.');
      }
      if (response.statusCode != 200) {
        return Err('Failed to load user (${response.statusCode})');
      }
      return Ok(GHUser.fromJson(await decodeJsonBody(response) as Map<String, Object?>));
    } catch (e) {
      return Err(_describe(e));
    }
  }

  /// Revokes the OAuth grant server-side (RFC 7009) so that signing out does not
  /// leave a live `repo`-scoped token behind on github.com.
  Future<Result<void>> revokeToken(String token) async {
    try {
      final response = await _client.post(
        Uri.parse(
          '${AppConstants.githubApiBase}/applications/${AppConstants.githubClientId}/token',
        ),
        headers: {..._headers(token), 'Content-Type': 'application/json'},
        body: jsonEncode({'access_token': token}),
      );
      if (response.statusCode == 200 || response.statusCode == 204) {
        return const Ok(null);
      }
      return Err('GitHub refused to revoke the token (${response.statusCode}).');
    } catch (e) {
      return Err(_describe(e));
    }
  }

  /// Turn an exception into something safe to show a user. Network and TLS
  /// failures get a specific, actionable message; anything else keeps its own
  /// text so real diagnostics are not swallowed.
  static String _describe(Object error) {
    if (error is HandshakeException) return error.message;
    if (error is TimeoutException) return 'The request timed out.';
    if (error is SocketException) return 'Could not reach GitHub.';
    if (error is HttpException) return 'Unexpected response from GitHub.';
    if (error is http.ClientException) return 'Network error: ${error.message}';
    return error.toString();
  }

  Future<Result<List<GHRepo>>> listRepos(String token) =>
      _get('/user/repos', (items) => items.cast<Map<String, Object?>>().map(GHRepo.fromJson).toList(),
          token: token);

  Future<Result<List<GHBranch>>> listBranches(String token, String repo) => _get(
        '/repos/$repo/branches',
        (items) => items.cast<Map<String, Object?>>().map((j) => GHBranch.fromJson(j)).toList(),
        token: token,
      );

  Future<Result<List<GHCommit>>> listCommits(String token, String repo, String branch) => _get(
        '/repos/$repo/commits',
        (items) => items.cast<Map<String, Object?>>().map((j) => GHCommit.fromJson(j)).toList(),
        token: token,
        query: {'sha': branch},
      );

  static String _repoPath(String owner, String repo) =>
      '/repos/${Uri.encodeComponent(owner)}/${Uri.encodeComponent(repo)}';

  /// Workflow ids are accepted by GitHub either as a number or as the file name
  /// (`build-apk.yml`); a full `.github/workflows/...` path is not, so the last
  /// segment is what goes into the URL.
  static String _workflowSegment(String workflowId) {
    final trimmed = workflowId.replaceAll(r'\', '/');
    final name = trimmed.split('/').last;
    return Uri.encodeComponent(name);
  }

  Future<Result<List<T>>> _getListField<T>(
    String path,
    String field,
    T Function(Map<String, Object?>) parse, {
    required String? token,
    Map<String, String>? query,
  }) async {
    try {
      final uri = Uri.parse('${AppConstants.githubApiBase}$path')
          .replace(queryParameters: {...?query, 'per_page': '$_perPage'});
      final response = await _client.get(uri, headers: _headers(token));
      if (response.statusCode == 401) return Err('Unauthorized — token expired. Re-login.');
      if (response.statusCode != 200) {
        return Err('GitHub API error ${response.statusCode}');
      }
      final body = await decodeJsonBody(response) as Map<String, Object?>;
      final items = (body[field] as List<Object?>? ?? const []).cast<Map<String, Object?>>();
      return Ok(items.map(parse).toList());
    } catch (e) {
      return Err(_describe(e));
    }
  }

  Future<Result<T>> _getOne<T>(
    String path,
    T Function(Map<String, Object?>) parse, {
    required String? token,
  }) async {
    try {
      final response = await _client.get(
        Uri.parse('${AppConstants.githubApiBase}$path'),
        headers: _headers(token),
      );
      if (response.statusCode == 401) return Err('Unauthorized — token expired. Re-login.');
      if (response.statusCode != 200) {
        return Err('GitHub API error ${response.statusCode}');
      }
      return Ok(parse(await decodeJsonBody(response) as Map<String, Object?>));
    } catch (e) {
      return Err(_describe(e));
    }
  }

  Future<Result<List<GHWorkflow>>> listWorkflows(
    String token, {
    required String owner,
    required String repo,
  }) =>
      _getListField(
        '${_repoPath(owner, repo)}/actions/workflows',
        'workflows',
        GHWorkflow.fromJson,
        token: token,
      );

  Future<Result<void>> dispatchWorkflow(
    String token, {
    required String owner,
    required String repo,
    required String workflowId,
    required String ref,
    Map<String, dynamic>? inputs,
  }) async {
    try {
      final response = await _client.post(
        Uri.parse(
          '${AppConstants.githubApiBase}${_repoPath(owner, repo)}'
          '/actions/workflows/${_workflowSegment(workflowId)}/dispatches',
        ),
        headers: {..._headers(token), 'Content-Type': 'application/json'},
        body: jsonEncode({
          'ref': ref,
          if (inputs != null && inputs.isNotEmpty) 'inputs': inputs,
        }),
      );
      if (response.statusCode == 401) return Err('Unauthorized — token expired. Re-login.');
      if (response.statusCode == 204) return const Ok(null);
      return Err('GitHub refused the build (${response.statusCode}). '
          'Check the workflow exists on branch "$ref".');
    } catch (e) {
      return Err(_describe(e));
    }
  }

  Future<Result<List<GHWorkflowRun>>> listWorkflowRuns(
    String token, {
    required String owner,
    required String repo,
    String? workflowId,
  }) =>
      _getListField(
        '${_repoPath(owner, repo)}/actions/runs',
        'workflow_runs',
        GHWorkflowRun.fromJson,
        token: token,
        query: {if (workflowId != null) 'workflow_id': workflowId},
      );

  Future<Result<GHWorkflowRun>> getWorkflowRun(
    String token, {
    required String owner,
    required String repo,
    required int runId,
  }) =>
      _getOne(
        '${_repoPath(owner, repo)}/actions/runs/$runId',
        GHWorkflowRun.fromJson,
        token: token,
      );

  Future<Result<List<GHArtifact>>> listRunArtifacts(
    String token, {
    required String owner,
    required String repo,
    required int runId,
  }) =>
      _getListField(
        '${_repoPath(owner, repo)}/actions/runs/$runId/artifacts',
        'artifacts',
        GHArtifact.fromJson,
        token: token,
      );

  Future<Result<List<GHJobSummary>>> listRunJobs(
    String token, {
    required String owner,
    required String repo,
    required int runId,
  }) =>
      _getListField(
        '${_repoPath(owner, repo)}/actions/runs/$runId/jobs',
        'jobs',
        GHJobSummary.fromJson,
        token: token,
      );

  /// First leg of a download: the API answers 302 to a signed CDN URL.
  ///
  /// Redirects are followed by hand for two reasons: the Authorization header
  /// must not travel to the CDN, and [PinnedHttpClient] refuses hosts it has no
  /// pin for, so the redirect target needs a plain client.
  ///
  /// shortcut: the CDN leg trusts the system CA store instead of a pin — those
  /// hostnames rotate (Fastly, Azure) and a pinned leaf goes stale. Upgrade to a
  /// pinned download proxy if artifact tampering becomes a real threat.
  Future<Result<List<int>>> _download(
    Uri apiUri, {
    required String token,
    required int maxBytes,
  }) async {
    try {
      final request = http.Request('GET', apiUri)
        ..headers.addAll(_headers(token))
        ..followRedirects = false;
      final response = await _client.send(request);
      await response.stream.drain<void>();

      if (response.statusCode != 302 && response.statusCode != 200) {
        return Err('GitHub API error ${response.statusCode}');
      }
      Uri target = apiUri;
      if (response.statusCode == 302) {
        final location = response.headers['location'];
        if (location == null) return Err('GitHub returned no download location.');
        target = apiUri.resolve(location);
      }

      final download = http.Request('GET', target)..followRedirects = true;
      final stream = await _downloadClient.send(download).timeout(const Duration(minutes: 2));
      if (stream.statusCode != 200) {
        return Err('Download failed (${stream.statusCode}).');
      }
      final bytes = <int>[];
      await for (final chunk in stream.stream) {
        bytes.addAll(chunk);
        if (bytes.length > maxBytes) {
          return Err('Download is larger than ${maxBytes ~/ (1024 * 1024)} MB.');
        }
      }
      return Ok(bytes);
    } catch (e) {
      return Err(_describe(e));
    }
  }

  /// Downloads a run artifact ZIP.
  Future<Result<List<int>>> downloadArtifact(
    String token, {
    required String owner,
    required String repo,
    required int artifactId,
    int maxBytes = 256 * 1024 * 1024,
  }) =>
      _download(
        Uri.parse(
          '${AppConstants.githubApiBase}${_repoPath(owner, repo)}'
          '/actions/artifacts/$artifactId/zip',
        ),
        token: token,
        maxBytes: maxBytes,
      );

  /// Downloads the log of one job, as plain text.
  Future<Result<String>> jobLogs(
    String token, {
    required String owner,
    required String repo,
    required int jobId,
    int maxBytes = 4 * 1024 * 1024,
  }) async {
    final result = await _download(
      Uri.parse('${AppConstants.githubApiBase}${_repoPath(owner, repo)}/actions/jobs/$jobId/logs'),
      token: token,
      maxBytes: maxBytes,
    );
    return result.fold(
      (bytes) => Ok(utf8.decode(bytes, allowMalformed: true)),
      (error) => Err<String>(error),
    );
  }

  void close() {
    _client.close();
    if (!identical(_client, _downloadClient)) _downloadClient.close();
  }
}