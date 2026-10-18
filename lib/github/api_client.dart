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

  GitHubApiClient({http.Client? client})
      : _client = client ?? PinnedHttpClient.create();

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
      if (response.statusCode == 401) return Err('Unauthorized — token rejected.');
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

  /// Exception text can embed the request URI. Keep it presentable and never
  /// echo anything credential-shaped back to the UI.
  static String _describe(Object error) {
    if (error is http.ClientException) return 'Network error: ${error.message}';
    if (error is HandshakeException) return error.message;
    if (error is TimeoutException) return 'The request timed out.';
    if (error is SocketException) return 'Could not reach GitHub.';
    if (error is HttpException) return 'Unexpected response from GitHub.';
    return 'Request failed.';
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

  void close() => _client.close();
}