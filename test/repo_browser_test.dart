import 'package:kriya_code/core/di.dart';
import 'package:kriya_code/core/result.dart';
import 'package:kriya_code/github/api_client.dart';
import 'package:kriya_code/github/models.dart';
import 'package:kriya_code/github/ui/repo_browser.dart';
import 'package:kriya_code/workspace/fs_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeGitHubApiClient extends Fake implements GitHubApiClient {
  final List<GHRepo> testRepos;

  _FakeGitHubApiClient(this.testRepos);

  @override
  Future<Result<List<GHRepo>>> listRepos(String token) async {
    return Ok(testRepos);
  }
}

class _FakeFsService extends Fake implements FsService {
  @override
  bool exists(String path) {
    return path.contains('b-code/.git');
  }
}

void main() {
  tearDown(() {
    sl.reset();
  });

  testWidgets('renders search, filters, and repository cards', (tester) async {
    sl.reset();
    final repos = [
      GHRepo(
        fullName: 'adityagusain273/b-code',
        description: 'Mobile code editor for Android',
        isPrivate: false,
        defaultBranch: 'main',
        updatedAt: DateTime.now().subtract(const Duration(hours: 2)),
        language: 'Dart',
        stargazersCount: 5,
      ),
      GHRepo(
        fullName: 'adityagusain273/b-code-app',
        description: '',
        isPrivate: true,
        defaultBranch: 'main',
        updatedAt: DateTime.now().subtract(const Duration(days: 3)),
        language: 'Kotlin',
        stargazersCount: 0,
      ),
    ];

    sl.registerSingleton<GitHubApiClient>(_FakeGitHubApiClient(repos));
    sl.registerSingleton<FsService>(_FakeFsService());

    await tester.pumpWidget(
      MaterialApp(
        home: RepoBrowser(
          token: 'dummy-token',
          onSignOut: () async {},
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Your Repositories'), findsOneWidget);
    expect(find.text('Search repositories…'), findsOneWidget);
    expect(find.text('All (2)'), findsOneWidget);
    expect(find.text('Cloned (1)'), findsOneWidget);
    expect(find.text('Public (1)'), findsOneWidget);
    expect(find.text('Private (1)'), findsOneWidget);

    expect(find.text('b-code'), findsOneWidget);
    expect(find.text('b-code-app'), findsOneWidget);
    expect(find.text('Cloned'), findsOneWidget);
    expect(find.text('Dart'), findsOneWidget);
    expect(find.text('Kotlin'), findsOneWidget);

    // Test search filter
    await tester.enterText(find.byType(TextField), 'app');
    await tester.pumpAndSettle();

    expect(find.text('b-code-app'), findsOneWidget);
    expect(find.text('b-code'), findsNothing);

    // Clear search
    await tester.tap(find.byIcon(Icons.clear_rounded));
    await tester.pumpAndSettle();

    expect(find.text('b-code'), findsOneWidget);
    expect(find.text('b-code-app'), findsOneWidget);

    // Filter by Cloned
    await tester.tap(find.text('Cloned (1)'));
    await tester.pumpAndSettle();

    expect(find.text('b-code'), findsOneWidget);
    expect(find.text('b-code-app'), findsNothing);
  });
}
