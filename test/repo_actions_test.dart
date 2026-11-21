import 'package:kriya_code/core/di.dart';
import 'package:kriya_code/github/models.dart';
import 'package:kriya_code/github/ui/repo_actions.dart';
import 'package:kriya_code/workspace/fs_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeFsService extends Fake implements FsService {
  final bool isCloned;

  _FakeFsService({required this.isCloned});

  @override
  String get rootPath => '/test/workspace';

  @override
  bool exists(String path) {
    return isCloned;
  }
}

void main() {
  tearDown(() {
    sl.reset();
  });

  testWidgets('renders uncloned repo with Clone to Workspace button',
      (tester) async {
    sl.reset();
    sl.registerSingleton<FsService>(_FakeFsService(isCloned: false));

    final repo = GHRepo(
      fullName: 'adityagusain273/b-code',
      description: 'Mobile code editor for Android',
      isPrivate: false,
      defaultBranch: 'main',
      updatedAt: DateTime.now(),
      language: 'Dart',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: RepoActionsPage(repo: repo, token: 'token'),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('b-code'), findsNWidgets(2)); // in AppBar and card
    expect(find.text('adityagusain273/b-code'), findsOneWidget);
    expect(find.text('Mobile code editor for Android'), findsOneWidget);
    expect(find.text('default: main'), findsOneWidget);
    expect(find.text('Workspace Status: Not Cloned'), findsOneWidget);
    expect(find.text('Clone to Workspace'), findsOneWidget);
    expect(find.text('Cloud Build / CI'), findsOneWidget);
    expect(find.text('View Commit History'), findsOneWidget);
  });

  testWidgets('renders cloned repo with Open Cloned Copy button',
      (tester) async {
    sl.reset();
    sl.registerSingleton<FsService>(_FakeFsService(isCloned: true));

    final repo = GHRepo(
      fullName: 'adityagusain273/b-code',
      description: 'Mobile code editor for Android',
      isPrivate: false,
      defaultBranch: 'main',
      updatedAt: DateTime.now(),
      language: 'Dart',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: RepoActionsPage(repo: repo, token: 'token'),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Workspace Status: Cloned'), findsOneWidget);
    expect(find.text('Open Cloned Copy'), findsOneWidget);
  });
}
