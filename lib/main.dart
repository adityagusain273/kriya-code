import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_app/flutter_secure_app.dart';
import 'package:git2dart/git2dart.dart' as git;

import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/constants.dart';
import 'core/crash_reporter.dart';
import 'core/di.dart';
import 'core/pinned_http.dart';
import 'editor/highlighting/highlight_engine.dart';
import 'editor/snippets.dart';
import 'editor/highlighting/highlight_service.dart';
import 'editor/highlighting/packs/css_pack.dart';
import 'editor/highlighting/packs/c_pack.dart';
import 'editor/highlighting/packs/cpp_pack.dart';
import 'editor/highlighting/packs/html_pack.dart';
import 'editor/highlighting/packs/java_pack.dart';
import 'editor/highlighting/packs/javascript_pack.dart';
import 'editor/highlighting/packs/json_pack.dart';
import 'editor/highlighting/packs/markdown_pack.dart';
import 'editor/highlighting/packs/python_pack.dart';
import 'editor/highlighting/packs/typescript_pack.dart';
import 'editor/tab_manager.dart';
import 'execution/local/local_runner.dart';
import 'execution/runtime_download_service.dart';
import 'execution/runner_service.dart';
import 'github/api_client.dart';
import 'github/auth/device_flow_auth.dart';
import 'github/auth/token_store.dart';
import 'github/git_service.dart';
import 'monetization/entitlement_service.dart';
import 'plugins/builtin/builtin_extensions.dart';
import 'plugins/host/extension_install_store.dart';
import 'plugins/host/extension_registry.dart';
import 'plugins/host/language_registry.dart';
import 'servers/server_monitor.dart';
import 'settings/settings_store.dart';
import 'workspace/explorer_prefs.dart';
import 'workspace/fs_root.dart';
import 'workspace/workspace_service.dart';
import 'workspace/fs_service.dart';

Future<void> main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    // Release builds otherwise paint Flutter's anonymous grey box when a widget
    // throws, which is indistinguishable from a hang. Show that it is an error
    // and send the user to the crash log instead of leaving a dead screen.
    if (kReleaseMode) {
      ErrorWidget.builder = (_) => const _RenderFailureScreen();
    }

    try {
      await _initCrashReporterAndRasp().timeout(const Duration(seconds: 10));
    } catch (error, stack) {
      CrashReporter.recordZoneError(error, stack);
    }
    try {
      await _bootstrap();
    } catch (error, stack) {
      // Without this, a bootstrap failure left the process alive with no widget
      // tree at all: a black screen and a log line nobody reads. Show the error
      // instead, and keep the details in the crash log.
      CrashReporter.recordZoneError(error, stack);
      runApp(_BootstrapFailureApp(error: error.toString()));
      return;
    }
    runApp(const RootWidget());
  }, (error, stack) {
    CrashReporter.recordZoneError(error, stack);
  });
}

class _BootstrapFailureApp extends StatelessWidget {
  final String error;

  const _BootstrapFailureApp({required this.error});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4FC3F7)),
        useMaterial3: true,
      ),
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48),
                const SizedBox(height: 16),
                const Text(
                  'B Code could not start',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'This is usually a missing build flag. Full details are in the '
                  'crash log (Settings → report a bug).',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                SelectableText(
                  error,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RenderFailureScreen extends StatelessWidget {
  const _RenderFailureScreen();

  @override
  Widget build(BuildContext context) {
    return const Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: Color(0xFF1A1C1E),
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, color: Color(0xFFE0E0E0), size: 40),
                SizedBox(height: 12),
                Text(
                  'This screen failed to draw.\n'
                  'Reopen B Code. If it repeats, the details are in the crash log.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFFE0E0E0), fontSize: 14),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _initCrashReporterAndRasp() async {
  final crashEnabled = await _initCrashReporter();
  await CrashReporter.init(enabled: crashEnabled);

  // Never call exit() from here.
  //
  // The previous implementation killed the process on any detected threat, and
  // two of its checks were guaranteed to fire: `checkOfficialStore` refuses any
  // sideloaded, F-Droid, or adb-installed build, and `checkDeviceIdSpoofing`
  // compares AndroidDeviceInfo.id, which is Build.ID and therefore changes on
  // every OTA. Either one produced an app that silently dies on launch with no
  // UI and no recovery path.
  //
  // A rooted or hooked device is the attacker's win condition, not a reason to
  // brick the device. Record the finding and let the individual feature decide.
  await FlutterSecureApp().init(
    isEnabled: !kDebugMode,
    isProdEnv: !kDebugMode,
    checkJailbreakOrHooking: !kDebugMode,
    checkDebugger: !kDebugMode,
    checkEmulator: false,
    checkAppSignature: !kDebugMode,
    checkOfficialStore: false,
    // The binding token is written to both secure storage and prefs, which do
    // not stay in sync across a reinstall or data restore: this fired on every
    // launch of an ordinary sideloaded build. Nothing acts on the finding, so it
    // only dirtied the crash log.
    checkDeviceBinding: false,
    // Compares Build.ID, which rotates with OS updates. It detects nothing and
    // breaks the app after the first system update.
    checkDeviceIdSpoofing: false,
    // SHA-256 of android/key.jks (the release signing certificate), also used
    // by the CI workflow's signature gate.
    validAndroidSignatures: const [
      '97246D05F97C2BF1C4A839884849487FB0951D21CCFB03FACB1C1D33035251AE',
    ],
    onThreatDetected: (threat) {
      CrashReporter.recordZoneError(
        'RASP threat: ${threat.name}',
        StackTrace.current,
      );
      debugPrint('RASP threat detected: ${threat.name}');
    },
    onException: (error, stack) {
      CrashReporter.recordZoneError(error, stack);
      if (kDebugMode) debugPrint('SecureApp exception: $error\n$stack');
    },
  );
}

Future<bool> _initCrashReporter() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('crash_reporting_enabled') ?? true;
  } catch (_) {
    return true;
  }
}

class RootWidget extends StatelessWidget {
  const RootWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: sl<TabManager>()),
        ChangeNotifierProvider.value(value: sl<RunnerService>()),
      ],
      child: BCodeApp(settings: sl<SettingsStore>()),
    );
  }
}

Future<String> _resolveWorkspaceRoot(WorkspaceService workspace) async {
  final docsDir = await getApplicationDocumentsDirectory();
  final privatePath = '${docsDir.path}/projects';
  Directory(privatePath).createSync(recursive: true);
  final location = await workspace.resolve(privatePath);
  if (location.needsAllFilesAccess) {
    debugPrint('Shared workspace requested but not granted; using app-private.');
  }
  return location.path;
}

/// Enables the language packs for the languages chosen during onboarding.
///
/// A pack is bundled Dart code, not a download, so making the user install it by
/// hand only produced an error after they had already pressed Run. Installing the
/// *runtime* stays an explicit, on-demand step, the way a desktop editor installs a
/// language pack: the user chooses, and a new version arrives without an app
/// release.
Future<void> _prepareLanguagePacks() async {
  try {
    final store = sl<ExtensionInstallStore>();
    for (final language in sl<SettingsStore>().primaryLanguages) {
      store.install('bcode.lang.$language');
    }
  } catch (e) {
    debugPrint('Language pack setup failed: $e');
  }
}

Future<void> _bootstrap() async {
  final prefs = await SharedPreferences.getInstance();
  final workspaceService = WorkspaceService(prefs);
  sl.registerSingleton<WorkspaceService>(workspaceService);
  final rootPath = await _resolveWorkspaceRoot(workspaceService);
  Directory(rootPath).createSync(recursive: true);
  sl.registerSingleton(FsRoot(rootPath));
  final fsService = FsService(rootPath);
  sl.registerSingleton<FsService>(fsService);
  // Register initial root path with exec sandbox
  await setSandboxPaths([rootPath]);

  if (const bool.fromEnvironment('BCODE_EXEC_SELFTEST')) {
    unawaited(_execSelfTest(rootPath));
  }

  final settingsStore = SettingsStore(prefs);
  sl.registerSingleton<SettingsStore>(settingsStore);
  sl.registerSingleton<ExplorerPrefs>(ExplorerPrefs(prefs));
  sl.registerSingleton<ExtensionInstallStore>(ExtensionInstallStore(prefs));

  final docsSupportDir = await getApplicationSupportDirectory();
  final localRunner = LocalRunner();
  sl.registerSingleton<LocalRunner>(localRunner);
  // Native executables arrive over this channel, so it pins TLS exactly like
  // the GitHub traffic. A runtime .deb can far exceed the default body cap.
  final runtimeDownloads = RuntimeDownloadService(
    client: PinnedHttpClient.create(maxBytes: 512 * 1024 * 1024),
    prefs: prefs,
    extractor: localRunner.extractRuntime,
    runtimesRootResolver: () async =>
        await localRunner.runtimeRoot() ??
        '${docsSupportDir.path}/runtimes',
  );
  sl.registerSingleton<RuntimeDownloadService>(runtimeDownloads);
  unawaited(_prepareLanguagePacks());
  // Snippets live in the package as asset files. Without this call the nine files
  // under assets/snippets/ were never read and only the handful of hard-coded
  // snippets were offered.
  unawaited(SnippetService.loadAssets().catchError((Object e) {
    debugPrint('Snippet loading failed: $e');
  }));

  sl.registerSingleton<TokenStore>(TokenStore());


  final clientId = AppConstants.githubClientId.isEmpty
      // Debug builds start without a real OAuth app so that a plain
      // `flutter run` or adb install gives you a working editor. GitHub sign-in
      // reports that it is unavailable instead of failing a network request
      // against an unknown app.
      ? (kReleaseMode
          ? throw StateError(
              'GITHUB_CLIENT_ID is not set. Build with '
              '--dart-define=GITHUB_CLIENT_ID=<your GitHub OAuth App client id>.',
            )
          : AppConstants.unconfiguredClientId)
      : AppConstants.githubClientId;

  // Both the OAuth exchange and the API share one pinned client. The token is
  // minted by the exchange, so leaving it unpinned meant the most valuable
  // request in the app was the only one without integrity protection.
  final githubHttp = PinnedHttpClient.create();
  sl.registerSingleton<DeviceFlowAuth>(
    DeviceFlowAuth(clientId: clientId, client: githubHttp),
  );
  sl.registerSingleton<GitHubApiClient>(GitHubApiClient(client: githubHttp));

  try {
    await git.PlatformSpecific.initialize();
  } catch (_) {}

  sl.registerSingleton<GitService>(GitService());
  sl.registerSingleton<GitIdentityProvider>(GitIdentityProvider());
  sl.registerSingleton<RunnerService>(
    RunnerService(local: localRunner),
  );

  final registry = ExtensionRegistry();
  await registry.loadAll(builtinExtensions);
  sl.registerSingleton<ExtensionRegistry>(registry);
  sl.registerSingleton<LanguageRegistry>(registry.languageRegistry);

  final engine = HighlightEngine()
    ..register(PythonPack())
    ..register(JavaPack())
    ..register(CPack())
    ..register(CppPack())
    ..register(JavascriptPack())
    ..register(TypeScriptPack())
    ..register(HtmlPack())
    ..register(CssPack())
    ..register(JsonPack())
    ..register(MarkdownPack());
  sl.registerSingleton<HighlightEngine>(engine);

  sl.registerSingleton<HighlightService>(
    HighlightService(registry: registry.languageRegistry, engine: engine),
  );
  sl.registerSingleton<TabManager>(
    TabManager(
      fs: sl<FsService>(),
      highlight: sl<HighlightService>(),
      engine: engine,
    ),
  );
  sl<TabManager>().attachSettings(settingsStore);

  sl.registerSingleton<EntitlementService>(const FreeEntitlementService());
  sl.registerSingleton<ServerMonitor>(ServerMonitor(prefs));
}
Future<void> _execSelfTest(String workspaceRoot) async {
  const marker = 'BCODE_EXEC_SELFTEST';

  final probeDir = const String.fromEnvironment('BCODE_PROBE_DIR');
  if (probeDir.isNotEmpty) {
    for (final probe in const ['probe_static', 'probe_dyn']) {
      final path = '$probeDir/$probe';
      await _probe(marker, 'direct $probe', [path]);
      await _probe(marker, 'linker $probe', ['/system/bin/linker64', path]);
    }
    // Exercise the real ExecPlugin path (argv validation, sandbox check, the
    // linker launch and LD_LIBRARY_PATH) instead of Process.run directly.
    try {
      const execChannel = MethodChannel(AppConstants.execChannel);
      final r = await execChannel.invokeMapMethod<Object?, Object?>('exec', {
        'argv': ['$probeDir/probe_dyn'],
        'cwd': probeDir,
        'env': <String, String>{},
      });
      debugPrint(
        '$marker ExecPlugin exec exit=${r?['exitCode']} out=${(r?['stdout'] ?? '').toString().trim()}',
      );
    } catch (e) {
      debugPrint('$marker ExecPlugin exec THREW $e');
    }

    final libProbe = '$probeDir/libtest/probe2lib';
    await _probe(
      marker,
      'linker + private lib, no LD_LIBRARY_PATH',
      ['/system/bin/linker64', libProbe],
    );
    await _probe(
      marker,
      'linker + private lib, LD_LIBRARY_PATH',
      ['/system/bin/linker64', libProbe],
      environment: {'LD_LIBRARY_PATH': '$probeDir/libtest'},
    );
  }

  try {
    final support = await getApplicationSupportDirectory();
    final prefix = '${support.path}/runtimes/cpython';
    final python = '$prefix/bin/python3.14';
    final probe = File('$workspaceRoot/_selftest.py')
      ..writeAsStringSync('print("HELLO_FROM_PYTHON", 6 * 7)\n');
    final result = await Process.run(
      python,
      ['_selftest.py'],
      workingDirectory: workspaceRoot,
      environment: {
        'HOME': workspaceRoot,
        'PATH': '$prefix/bin:/system/bin',
        'LD_LIBRARY_PATH': '$prefix/lib',
        'TMPDIR': workspaceRoot,
      },
    );
    debugPrint('$marker root=$workspaceRoot exit=${result.exitCode} stdout=${result.stdout} stderr=${result.stderr}');
    probe.deleteSync();

    const shared = '/storage/emulated/0/BCode';
    try {
      final dir = Directory(shared);
      dir.createSync(recursive: true);
      final f = File('$shared/_selftest.txt')
        ..writeAsStringSync('shared-volume-ok\n');
      debugPrint('$marker shared_write=${f.readAsStringSync().trim()}');
    } catch (e) {
      debugPrint('$marker shared_throw=$e');
    }
  } catch (e) {
    debugPrint('$marker throw=$e');
  }
}

Future<void> _probe(
  String marker,
  String label,
  List<String> argv, {
  Map<String, String>? environment,
}) async {
  try {
    final r = await Process.run(
      argv.first,
      argv.skip(1).toList(),
      environment: environment,
    );
    debugPrint('$marker $label exit=${r.exitCode} out=${(r.stdout as String).trim()} err=${(r.stderr as String).trim()}');
  } catch (e) {
    debugPrint('$marker $label THREW $e');
  }
}
