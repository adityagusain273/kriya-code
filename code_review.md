Most recent local review with findings: 23 stored findings
Review directory: ~/USB drive1/b_code
Base branch: master

────────────────────────────────────────────────────────────────────────
  minor [Maintainability & Code Quality]
  → README.md:15

  Correct the documented execution model.

  The README describes an automatic cloud fallback to Piston and a
  LOCAL/CLOUD label on every run. The code has neither:
  - ExecutionMode has only local.
  - RunConfig has no cloud target.
  - RunnerService reports `'No local runtime configured for this
  language.'` when no local runtime exists.

  Lines 65-71 repeat the same claim. Update both sections to match the local
  and Termux execution model.


────────────────────────────────────────────────────────────────────────
  major [Data Integrity & Integration]
  → test/runtime_download_test.dart:119

  Use a unique directory for each test run.

  tearDown deletes /tmp/bcode_test_runtimes recursively, even if the
  directory existed before this test. A user or another process can lose
  files stored at that path. Create a temporary directory in setUp, pass
  its path to runtimesRootResolver, and delete only that directory.




  Also applies to: 125-126


────────────────────────────────────────────────────────────────────────
  minor [Stability & Availability]
  → lib/terminal/terminal_widget.dart:109-120

  Check mounted before setState in the PTY callbacks.

  dispose() kills the PTY. The onDone and exitCode.then callbacks then
  run after the widget is unmounted, and setState throws "setState()
  called after dispose()". This happens each time the console sheet closes
  or the terminal tab leaves the tree. "Restart shell" also lets the old
  PTY's callbacks change the state of the new session.


  Proposed fix

         onDone: () {
  -        setState(() => _isRunning = false);
  +        if (!mounted) return;
  +        setState(() => _isRunning = false);
           terminal.write('\r\n[process exited]\r\n');
         },
       );
  
       pty!.exitCode.then((code) {
  -      setState(() => _isRunning = false);
  +      if (!mounted) return;
  +      setState(() => _isRunning = false);


────────────────────────────────────────────────────────────────────────
  minor [Functional Correctness]
  → lib/editor/tab_manager.dart:168-176

  Adjust activeIndex when a tab before the active tab closes.

  close(index) changes activeIndex only when it is out of range. If
  `index
  Proposed fix

       tabs[index].controller.dispose();
  +    tabs[index].findController.dispose();
       tabs.removeAt(index);
  -    if (activeIndex >= tabs.length) activeIndex = tabs.length - 1;
  +    if (index < activeIndex) {
  +      activeIndex--;
  +    } else if (activeIndex >= tabs.length) {
  +      activeIndex = tabs.length - 1;
  +    }


────────────────────────────────────────────────────────────────────────
  major [Stability & Availability]
  → android/app/src/main/kotlin/com/bcode/editor/ExecPlugin.kt:245-270

  Do not execute extracted runtimes from filesDir on target SDK 35.

  When runtimesRoot() resolves to filesDir/runtimes,
  ProcessBuilder(argv).start() can select binaries from its bin entries.
  Android blocks execve for files in the writable app home directory when
  targetSdk >= 29, so these launches can fail with EACCES. Change the
  runtime delivery or launch path so executable files do not come from
  filesDir.

  The .deb RPATH and interpreter claim is not established by the supplied
  evidence.


────────────────────────────────────────────────────────────────────────
  major [Functional Correctness]
  → lib/editor/editor_page.dart:1069-1075

  Handle files outside the workspace root in "Open File".

  The file browser returns absolute paths under /storage/emulated/0.
  TabManager.open(path) calls fs.exists(path), and fs.exists calls
  FsService.resolve. resolve throws `ArgumentError('Path escapes
  workspace root') for any path outside rootPath`. As a result, "Open
  File" always fails for a file that is not in the current workspace, and
  the Future is not awaited or caught. Choose one fix:
  - Set the workspace root to the file's directory before open.
  - Let TabManager read and write external files without the sandbox
  check.

  Show an error message if both options are rejected.


────────────────────────────────────────────────────────────────────────
  major [Functional Correctness]
  → android/app/src/main/kotlin/com/bcode/editor/MainActivity.kt:109-110

  Get the import file name from OpenableColumns.DISPLAY_NAME.

  For SAF document URIs, uri.lastPathSegment is the document ID, for
  example primary:Download/foo.py or msf:1234. A value that contains /
  makes File(projectsDir(), name) point into a subdirectory that does not
  exist, and outputStream() throws. A provider can also return a segment
  that contains ../. Query DISPLAY_NAME and keep only the base name.


  Proposed fix

  -                        val name = uri.lastPathSegment ?: "imported.txt"
  +                        val display = contentResolver.query(uri, arrayOf(android.provider.OpenableColumns.DISPLAY_NAME), null, null, null)
  +                            ?.use { c -> if (c.moveToFirst()) c.getString(0) else null }
  +                        val name = File(display ?: "imported.txt").name


────────────────────────────────────────────────────────────────────────
  major [Performance & Scalability]
  → lib/github/git_service.dart:43-47

  Move blocking libgit2 operations off the UI isolate.

  git2dart makes synchronous FFI calls. The methods are async, but
  Repository.clone, push, fetch, and Diff still run on the UI
  isolate and block it for the whole network or disk operation. A large
  clone freezes the UI and can trigger an ANR. Run these operations in
  Isolate.run, and pass paths and the token instead of Repository
  handles.


────────────────────────────────────────────────────────────────────────
  minor [Functional Correctness]
  → update_qa.py:3

  Accept the QA report path as an input.

  On a machine without this developer-specific path, the first open()
  raises FileNotFoundError, so the script cannot update a report. Accept
  the report path as an argument and use that same path for the write at
  Line 16.


────────────────────────────────────────────────────────────────────────
  major [Data Integrity & Integration]
  → android/app/src/main/kotlin/com/bcode/editor/MainActivity.kt:29-33

  Write imports into the directory that the Dart workspace uses.

  projectsDir() resolves to filesDir/app_flutter/projects, which is
  /data/data//files/app_flutter/projects. On Android, Dart's
  getApplicationDocumentsDirectory() returns /app_flutter, so
  FsService.rootPath is /data/data//app_flutter/projects (see
  lib/main.dart lines 114-115). The file explorer never shows imported
  files. Also, Dart receives only dest.name, which it cannot resolve.


  Proposed fix

  -        val dir = File(filesDir, "app_flutter/projects")
  +        val dir = File(dataDir, "app_flutter/projects")


────────────────────────────────────────────────────────────────────────
  major [Functional Correctness]
  → lib/plugins/ui/extensions_page.dart:176-191

  Check the download result before the extension is marked installed.

  RuntimeDownloadService.download catches every error internally and
  records RuntimeDownloadPhase.failed. The call does not throw, so this
  catch never runs. _store.install(ext.id) then runs even when the
  runtime download or extraction failed. The editor then passes the
  extension gate in _runWithArgs, and every run fails with "Runtime not
  installed". Check _downloads.stateFor(runtimeId).phase after the
  await.


  Proposed fix

  -      try {
  -        await _downloads.download(runtimeId);
  -      } catch (e) {
  -        if (mounted) {
  -          ScaffoldMessenger.of(context).showSnackBar(
  -            SnackBar(content: Text('Failed to download runtime: $e')),
  -          );
  -        }
  -        return;
  -      }
  +      await _downloads.download(runtimeId);
  +      final state = _downloads.stateFor(runtimeId);
  +      if (state.phase != RuntimeDownloadPhase.installed) {
  +        if (mounted) {
  +          ScaffoldMessenger.of(context).showSnackBar(
  +            SnackBar(content: Text('Failed to download runtime: ${state.error ?? 'unknown error'}')),
  +          );
  +        }
  +        return;
  +      }


────────────────────────────────────────────────────────────────────────
  major [Functional Correctness]
  → android/app/src/main/kotlin/com/bcode/editor/TermuxPlugin.kt:63-72

  Check whether B Code holds RUN_COMMAND, not whether Termux requests it.

  isTermuxAllowed() looks for com.termux.permission.RUN_COMMAND in
  Termux's own requestedPermissions. Termux always declares that
  permission, so this check is always true. RUN_COMMAND is a dangerous
  permission that B Code must be granted at runtime. If it is not granted,
  startService throws SecurityException on every run.


  Proposed fix

  -        return try {
  -            val pkgInfo = appContext.packageManager.getPackageInfo(TERMUX_PACKAGE, PackageManager.GET_PERMISSIONS)
  -            val requestedPerms = pkgInfo.requestedPermissions ?: return false
  -            "com.termux.permission.RUN_COMMAND" in requestedPerms
  -        } catch (_: Exception) {
  -            false
  -        }
  +        return appContext.checkSelfPermission("com.termux.permission.RUN_COMMAND") ==
  +            PackageManager.PERMISSION_GRANTED


────────────────────────────────────────────────────────────────────────
  major [Data Integrity & Integration]
  → test_script.dart:4-8

  Do not delete an existing test_file.txt.

  If test_file.txt already exists in the working directory, createSync()
  does not make the file exclusive to this script, and deleteSync()
  removes it. Run the check in a newly created temporary directory and clean
  up that directory afterward.


────────────────────────────────────────────────────────────────────────
  minor [Stability & Availability]
  → lib/editor/editor_page.dart:208-211

  Call Scaffold.of with a context that is below the Scaffold.

  _onKeyEvent uses the State.context of _EditorPageState. That context
  is above the Scaffold that build creates. Scaffold.of(context)
  throws "Scaffold.of() called with a context that does not contain a
  Scaffold" on every Ctrl+B press. Use a GlobalKey.


  Proposed fix

  -      Scaffold.of(context).openDrawer();
  +      _scaffoldKey.currentState?.openDrawer();

  Declare final _scaffoldKey = GlobalKey(); and pass key: _scaffoldKey
  to the Scaffold.


────────────────────────────────────────────────────────────────────────
  major [Functional Correctness]
  → lib/editor/command_palette.dart:271-274

  Stop the double pop when a palette action runs.

  _execute pops the palette. Many actions then call
  Navigator.pop(context) again, for example Quick Open, Run, Show Console,
  Extensions, and Settings. The second pop removes the route under the
  palette, which is EditorPage. Its PopScope then shows the
  unsaved-changes dialog or leaves the editor. The action then runs
  Navigator.push(context, ...) or QuickOpen.show(context) with the
  palette's deactivated context, which throws. Remove the
  Navigator.pop(context) calls from the individual actions. Run each
  action after the pop, with a context that is still mounted.


────────────────────────────────────────────────────────────────────────
  major [Data Integrity & Integration]
  → lib/onboarding/onboarding_page.dart:105-110

  Restore the custom storage root at startup.

  _setCustomStorage saves custom_storage_path, but _bootstrap in
  lib/main.dart never reads it. FsService always starts at /projects.
  After the app restarts, the chosen folder is lost. restoreSession then
  calls fs.exists on tab paths outside the root, which throws. The catch
  aborts the whole session restore. _openFileBrowser(pickFolder: true) in
  editor_page.dart does not save the choice either.


  Proposed fix (lib/main.dart)

  final prefs = await SharedPreferences.getInstance();
  final custom = prefs.getString('custom_storage_path');
  final fs = FsService(rootPath);
  if (custom != null && Directory(custom).existsSync()) {
    await fs.setCustomRoot(custom);
  }
  sl.registerSingleton<FsService>(fs);


────────────────────────────────────────────────────────────────────────
  minor [Functional Correctness]
  → lib/settings/settings_page.dart:341-347

  Remove the simulated screenshot attachments.

  "Attach Screenshot" adds placeholder names such as Screenshot_1.png. No
  file is attached. The snackbar at line 375 then says "Feedback submitted
  with N screenshots", which is false. Either implement a real image picker
  or remove the attachment UI and the count from the message.


────────────────────────────────────────────────────────────────────────
  major [Functional Correctness]
  → test/extensions_page_test.dart:40-47

  Update the tests to match the current ExtensionsPage.

  ExtensionsPage has no "Run Python offline?" dialog. It has no "Download"
  or "Not now" buttons either, because _onInstallTap downloads directly.
  find.text('Run Python offline?') therefore finds nothing, and the first
  two tests fail. The test at lines 69-74 taps a Download button that does
  not exist. flutter test fails in the current state.


────────────────────────────────────────────────────────────────────────
  minor [Functional Correctness]
  → lib/editor/snippets.dart:145-146

  Use the AssetManifest API instead of AssetManifest.json.

  Newer Flutter versions no longer generate AssetManifest.json. The
  repository targets Flutter 3.47.
  rootBundle.loadString('AssetManifest.json') then throws, and asset
  snippets never load. TemplateService.loadAssets already uses the
  supported API.


  Proposed fix

  -    final manifest = await rootBundle.loadString('AssetManifest.json');
  -    final Map<String, dynamic> manifestMap = jsonDecode(manifest);
  -    
  -    for (final key in manifestMap.keys) {
  +    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
  +    for (final key in manifest.listAssets()) {


────────────────────────────────────────────────────────────────────────
  minor [Maintainability & Code Quality]
  → docs/EXTENSIONS.md:32-35

  Update the example to match the current RunConfig API.

  RunConfig has only a local field (see
  lib/plugins/api/run_config.dart). FallbackPolicy and CloudTarget do
  not exist, so this example does not compile. Lines 63-71 describe the same
  removed cloud semantics.


  Proposed fix

  -    runConfig: const RunConfig(
  -      policy: FallbackPolicy.cloudOnly,  // or preferLocalThenCloud with a LocalTarget
  -      cloud: CloudTarget(language: 'rust', version: '*'),
  -    ),
  +    runConfig: const RunConfig(
  +      local: LocalTarget(
  +        runtimeId: 'rust',
  +        runArgv: ['{runtimePath}/bin/rustc', '{file}'],
  +      ),
  +    ),


────────────────────────────────────────────────────────────────────────
  critical [Functional Correctness]
  → lib/execution/local/local_runner.dart:51-57

  Run the build step and the run step as separate processes.

  The code puts buildArgv and runArgv into one argv and sends a single
  exec call. For C, the result is clang file.c -o out.out out.out. Clang
  reads the output path as an extra input file, and the program never runs.
  For Java, the result is javac Main.java .../java -cp dir Main, which
  fails. Every language with a buildArgv (C, C++, Java) is broken. Call
  exec for the build step first. Run runArgv only if the build exits
  with code 0. Keep the build output in buildStdout and buildStderr,
  which the code at lines 72-79 already reads.


────────────────────────────────────────────────────────────────────────
  critical [Stability & Availability]
  → android/app/src/main/kotlin/com/bcode/editor/ExecPlugin.kt:119-125

  Reply to MethodChannel.Result on the main thread.

  result.success and result.error run on the executor worker thread.
  The same applies to extractRuntime at lines 91-98. Flutter requires
  platform channel replies on the platform (UI) thread. A reply from another
  thread fails with the error "Methods marked with @UiThread must be
  executed on the main thread". The Dart await can then fail to complete.
  TermuxPlugin.runTermuxCommand (lines 87-124) has the same defect.


  Proposed fix

  +    private val mainHandler = android.os.Handler(android.os.Looper.getMainLooper())
   ...
                       executor.submit {
  -                        try {
  -                            result.success(exec(argv, cwd, safeEnv, timeoutMs))
  -                        } catch (e: Exception) {
  -                            result.error("EXEC_FAILED", e.message, null)
  -                        }
  +                        try {
  +                            val r = exec(argv, cwd, safeEnv, timeoutMs)
  +                            mainHandler.post { result.success(r) }
  +                        } catch (e: Exception) {
  +                            mainHandler.post { result.error("EXEC_FAILED", e.message, null) }
  +                        }
                       }


────────────────────────────────────────────────────────────────────────
  minor [Functional Correctness]
  → lib/execution/local/local_runner.dart:102-109

  Pass RunRequest.args to the program.

  _substitute never uses request.args, and no runArgv template
  contains an argument token. "Run with Arguments"
  (_showRunWithArgsDialog) therefore runs without the arguments the user
  entered. Append request.args to the substituted runArgv.


  Proposed fix

  -      argv.addAll(
  -          _substitute(target.runArgv, runtimeDir, runtimePath, request, workDir));
  +      argv
  +        ..addAll(_substitute(target.runArgv, runtimeDir, runtimePath, request, workDir))
  +        ..addAll(request.args);

