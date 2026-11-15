import 'dart:convert';

import 'package:b_code/github/api_client.dart';
import 'package:b_code/github/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;

void main() {
  group('GitHub Actions endpoints', () {
    test('listWorkflows reads the workflows field', () async {
      final client = http_testing.MockClient((_) async => http.Response(
            jsonEncode({
              'total_count': 1,
              'workflows': [
                {'id': 42, 'name': 'Android APK', 'path': '.github/workflows/build-apk.yml', 'state': 'active'},
              ],
            }),
            200,
          ));

      final api = GitHubApiClient(client: client);
      final result = await api.listWorkflows('token', owner: 'me', repo: 'app');

      expect(result.isOk, isTrue);
      final workflows = result.valueOrNull!;
      expect(workflows.single.id, 42);
      expect(workflows.single.path, endsWith('build-apk.yml'));

      api.close();
    });

    test('dispatchWorkflow posts the ref and inputs', () async {
      late http.Request captured;
      final client = http_testing.MockClient((request) async {
        captured = request;
        return http.Response('', 204);
      });

      final api = GitHubApiClient(client: client);
      final result = await api.dispatchWorkflow(
        'token',
        owner: 'me',
        repo: 'app',
        workflowId: '.github/workflows/build-apk.yml',
        ref: 'main',
        inputs: {'build_type': 'debug'},
      );

      expect(result.isOk, isTrue);
      expect(captured.method, 'POST');
      expect(captured.url.path, '/repos/me/app/actions/workflows/build-apk.yml/dispatches');
      expect(jsonDecode(captured.body), {'ref': 'main', 'inputs': {'build_type': 'debug'}});

      api.close();
    });

    test('dispatchWorkflow explains a rejected dispatch', () async {
      final client = http_testing.MockClient((_) async => http.Response('not found', 404));

      final api = GitHubApiClient(client: client);
      final result = await api.dispatchWorkflow(
        'token',
        owner: 'me',
        repo: 'app',
        workflowId: '42',
        ref: 'main',
      );

      expect(result.isOk, isFalse);
      expect(result.errorOrNull, contains('404'));

      api.close();
    });

    test('listWorkflowRuns filters by workflow and parses timing', () async {
      late Uri captured;
      final client = http_testing.MockClient((request) async {
        captured = request.url;
        return http.Response(
          jsonEncode({
            'total_count': 1,
            'workflow_runs': [
              {
                'id': 7,
                'name': 'Android APK',
                'status': 'completed',
                'conclusion': 'success',
                'head_branch': 'main',
                'created_at': '2026-01-01T10:00:00Z',
                'updated_at': '2026-01-01T10:03:30Z',
              },
            ],
          }),
          200,
        );
      });

      final api = GitHubApiClient(client: client);
      final result =
          await api.listWorkflowRuns('token', owner: 'me', repo: 'app', workflowId: '42');

      expect(result.isOk, isTrue);
      expect(captured.queryParameters['workflow_id'], '42');
      final run = result.valueOrNull!.single;
      expect(run.isSuccess, isTrue);
      expect(run.duration, const Duration(minutes: 3, seconds: 30));

      api.close();
    });

    test('artifacts and steps parse', () async {
      final client = http_testing.MockClient((request) async {
        if (request.url.path.endsWith('/artifacts')) {
          return http.Response(
            jsonEncode({
              'total_count': 1,
              'artifacts': [
                {'id': 9, 'name': 'app-apk', 'size_in_bytes': 1048576, 'expired': false},
              ],
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'total_count': 1,
            'jobs': [
              {
                'id': 77,
                'name': 'build',
                'status': 'completed',
                'conclusion': 'success',
                'steps': [
                  {'name': 'Checkout', 'status': 'completed', 'conclusion': 'success'},
                ],
              },
            ],
          }),
          200,
        );
      });

      final api = GitHubApiClient(client: client);
      final artifacts =
          await api.listRunArtifacts('token', owner: 'me', repo: 'app', runId: 7);
      final jobs = await api.listRunJobs('token', owner: 'me', repo: 'app', runId: 7);

      expect(artifacts.valueOrNull!.single.name, 'app-apk');
      expect(artifacts.valueOrNull!.single.expired, isFalse);
      expect(jobs.valueOrNull!.single.id, 77);
      expect(jobs.valueOrNull!.single.steps.single.name, 'Checkout');

      api.close();
    });

    test('jobLogs decodes the redirected text body', () async {
      final apiClient = http_testing.MockClient((_) async => http.Response(
            '',
            302,
            headers: {'location': 'https://objects.example.com/job.log'},
          ));
      final downloadClient = http_testing.MockClient(
        (_) async => http.Response.bytes(utf8.encode('step 1: ok\nstep 2: ok'), 200),
      );

      final api = GitHubApiClient(client: apiClient, downloadClient: downloadClient);
      final result = await api.jobLogs('token', owner: 'me', repo: 'app', jobId: 77);

      expect(result.valueOrNull, 'step 1: ok\nstep 2: ok');

      api.close();
    });

    test('downloadArtifact follows the signed redirect without the token', () async {
      late http.Request apiRequest;
      final downloadRequests = <http.Request>[];

      final apiClient = http_testing.MockClient((request) async {
        apiRequest = request;
        return http.Response(
          '',
          302,
          headers: {'location': 'https://objects.example.com/artifact?sig=abc'},
        );
      });
      final downloadClient = http_testing.MockClient((request) async {
        downloadRequests.add(request);
        return http.Response.bytes([80, 75, 3, 4], 200);
      });

      final api = GitHubApiClient(client: apiClient, downloadClient: downloadClient);
      final result =
          await api.downloadArtifact('secret-token', owner: 'me', repo: 'app', artifactId: 9);

      expect(result.isOk, isTrue);
      expect(result.valueOrNull, [80, 75, 3, 4]);
      expect(apiRequest.headers['Authorization'], 'Bearer secret-token');
      expect(apiRequest.followRedirects, isFalse);
      expect(downloadRequests.single.url.host, 'objects.example.com');
      expect(downloadRequests.single.headers.containsKey('Authorization'), isFalse);

      api.close();
    });
  });

  group('workflow models', () {
    test('missing fields do not throw', () {
      expect(GHWorkflow.fromJson({}).id, 0);
      expect(GHWorkflowRun.fromJson({}).status, '');
      expect(GHWorkflowRun.fromJson({}).isFinished, isFalse);
      expect(GHArtifact.fromJson({}).expired, isFalse);
      expect(GHJobSummary.fromJson({}).steps, isEmpty);
    });

    test('duration is null until the run finishes', () {
      final run = GHWorkflowRun.fromJson({
        'status': 'in_progress',
        'created_at': '2026-01-01T10:00:00Z',
        'updated_at': '2026-01-01T10:01:00Z',
      });
      expect(run.duration, isNull);
    });
  });
}
