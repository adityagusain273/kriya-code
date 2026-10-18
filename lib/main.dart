import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_app/flutter_secure_app.dart';
import 'package:git2dart/git2dart.dart' as git;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/constants.dart';
import 'core/crash_reporter.dart';
import 'core/di.dart';
import 'core/pinned_http.dart';
import 'editor/highlighting/highlight_engine.dart';
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
import 'workspace/fs_service.dart';

Future<void> main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    await _initCrashReporterAndRasp();
    await _bootstrap();
    runApp(const RootWidget());
  }, (error, stack) {
    CrashReporter.recordZoneError(error, stack);
  });
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
    checkDeviceBinding: !kDebugMode,
    // Compares Build.ID, which rotates with OS updates. It detects nothing and
    // breaks the app after the first system update.
    checkDeviceIdSpoofing: false,
    validAndroidSignatures: const [
      '8C8BA3228E40E50B6448D98AF99D5C1854A8CFF81047171D8CD7728AE042277D',
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

class FsRoot {
  final String path;
  const FsRoot(this.path);
}

Future<void> _bootstrap() async {
  final docsDir = await getApplicationDocumentsDirectory();
  final rootPath = '${docsDir.path}/projects';
  Directory(rootPath).createSync(recursive: true);
  sl.registerSingleton(FsRoot(rootPath));
  final fsService = FsService(rootPath);
  sl.registerSingleton<FsService>(fsService);
  // Register initial root path with exec sandbox
  await fsService.registerSandboxPath(rootPath);

  final prefs = await SharedPreferences.getInstance();
  final settingsStore = SettingsStore(prefs);
  sl.registerSingleton<SettingsStore>(settingsStore);
  sl.registerSingleton<ExplorerPrefs>(ExplorerPrefs(prefs));
  sl.registerSingleton<ExtensionInstallStore>(ExtensionInstallStore(prefs));

  final docsSupportDir = await getApplicationSupportDirectory();
  final localRunner = LocalRunner();
  sl.registerSingleton<LocalRunner>(localRunner);
  sl.registerSingleton<RuntimeDownloadService>(RuntimeDownloadService(
    client: http.Client(),
    prefs: prefs,
    extractor: localRunner.extractRuntime,
    runtimesRootResolver: () async =>
        await localRunner.runtimeRoot() ??
        '${docsSupportDir.path}/runtimes',
  ));

  sl.registerSingleton<TokenStore>(TokenStore());

  final clientId = AppConstants.githubClientId;
  if (clientId.isEmpty) {
    throw StateError(
      'GITHUB_CLIENT_ID is not set. Build with '
      '--dart-define=GITHUB_CLIENT_ID=<your GitHub OAuth App client id>.',
    );
  }

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