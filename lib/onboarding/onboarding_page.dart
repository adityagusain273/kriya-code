
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/di.dart';
import '../workspace/import_actions.dart';

import '../editor/editor_page.dart';

import '../github/auth/device_flow_auth.dart';
import '../github/auth/token_store.dart';
import '../settings/settings_store.dart';
import '../execution/runtime_download_service.dart';
import '../execution/runtime_catalog.dart';


class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage>
    with TickerProviderStateMixin {
  final _pageCtrl = PageController();
  int _step = 0;

  late final AnimationController _welcomeAnim =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
        ..forward();
  late final AnimationController _featuresAnim =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
  late final AnimationController _langAnim =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 600));

  bool _githubDone = false;
  bool _connecting = false;
  String _status = '';

  final Set<String> _selectedLanguages = {};


  static const int _totalSteps = 6;


  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    _welcomeAnim.dispose();
    _featuresAnim.dispose();
    _langAnim.dispose();
    super.dispose();
  }

  void _next() {
    if (_step < _totalSteps) {
      _pageCtrl.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOutCubic,
      );
      setState(() => _step++);
      _triggerPageAnim(_step);
    } else {
      _finish();
    }
  }

  void _triggerPageAnim(int step) {
    switch (step) {
      case 1:
        _featuresAnim.forward(from: 0);
      case 2:
        _langAnim.forward(from: 0);
      case 6:
        _startSetup();
      default:
        break;
    }
  }

  void _skip() => _finish();

  void _finish() {
    // Setting the flag rebuilds the app shell, which swaps `home` to the editor.
    // Pushing a route as well used to stack a second EditorPage on top of it,
    // leaving two file explorers and two TabManager listeners alive.
    sl<SettingsStore>().onboardingComplete = true;
    if (mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const EditorPage()),
    );
  }


  Future<void> _connectGitHub() async {
    setState(() {
      _connecting = true;
      _status = 'Requesting device code…';
    });
    try {
      final auth = sl<DeviceFlowAuth>();
      final session = await auth.start();
      if (!mounted) return;
      await Clipboard.setData(ClipboardData(text: session.userCode));
      setState(() => _status = 'Code copied! Enter it on GitHub.');
      final timer = Stream.periodic(Duration(seconds: session.intervalSeconds));
      await for (final _ in timer) {
        final result = await auth.pollOnce(session);
        if (result.status == DeviceFlowStatus.success) {
          await sl<TokenStore>().write(result.token!);
          setState(() {
            _githubDone = true;
            _connecting = false;
            _status = 'Connected!';
          });
          return;
        }
        if (result.status != DeviceFlowStatus.pending) {
          setState(() {
            _connecting = false;
            _status = 'Login failed. You can skip this step.';
          });
          return;
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _connecting = false;
          _status = 'Error: $e';
        });
      }
    }
  }

  /// Unpacks a project archive the user picks off the device.
  ///
  /// This used to open a bespoke browser hardcoded to
  /// `/storage/emulated/0/Download`, which needs a storage permission the app does not
  /// hold and so listed nothing on most devices, and it only recognised `.zip`. It now
  /// goes through the same system picker as the editor's "Unzip Project" action and
  /// handles tar and gzip too.
  Future<void> _extractZip() async {
    await importArchiveFromDevice(context);
  }

  Widget _buildDots(ColorScheme cs) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
        _totalSteps + 1,
        (i) => AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: _step == i ? 22 : 6,
          height: 6,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(3),
            color: _step == i
                ? cs.primary
                : cs.onSurface.withValues(alpha: 0.18),
          ),
        ),
      ),
    );
  }

  Widget _navRow({bool continueEnabled = true}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        if (_step == 0)
          TextButton(onPressed: _skip, child: const Text('Skip'))
        else
          TextButton(
            onPressed: () {
              _pageCtrl.previousPage(
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeInOutCubic,
              );
              setState(() => _step--);
            },
            child: const Text('Back'),
          ),
        FilledButton(
          onPressed: continueEnabled ? _next : null,
          child: Text(_step == _totalSteps ? 'Start Coding' : 'Continue'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: PageView(
          controller: _pageCtrl,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _buildWelcome(cs),
            _buildFeatures(cs),
            _buildLanguagePicker(cs),
            _buildStorage(cs),
            _buildGitHub(cs),
            _buildRunCode(cs),
            _buildSetupEnvironment(cs),
          ],
        ),
      ),
    );
  }


  Widget _buildWelcome(ColorScheme cs) {
    final logoScale = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _welcomeAnim, curve: Curves.elasticOut),
    );
    final fade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
          parent: _welcomeAnim,
          curve: const Interval(0.3, 1.0, curve: Curves.easeOut)),
    );

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            cs.primaryContainer,
            cs.surface,
            cs.secondaryContainer.withValues(alpha: 0.4),
          ],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Spacer(),
            ScaleTransition(
              scale: logoScale,
              child: Container(
                width: 110,
                height: 110,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: cs.primary,
                  boxShadow: [
                    BoxShadow(
                      color: cs.primary.withValues(alpha: 0.45),
                      blurRadius: 32,
                      spreadRadius: 6,
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    'B',
                    style: TextStyle(
                      fontSize: 58,
                      fontWeight: FontWeight.w900,
                      color: cs.onPrimary,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),
            FadeTransition(
              opacity: fade,
              child: Column(
                children: [
                  Text(
                    'B Code',
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Code. Build. Ship.\nRight from your phone.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: cs.onSurfaceVariant,
                          height: 1.5,
                        ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            FadeTransition(
              opacity: fade,
              child: Column(
                children: [
                  FilledButton.icon(
                    onPressed: _next,
                    icon: const Icon(Icons.arrow_forward_rounded),
                    label: const Text('Get Started'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(220, 52),
                      textStyle: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                      onPressed: _skip, child: const Text('Skip setup')),
                  const SizedBox(height: 20),
                  _buildDots(cs),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatures(ColorScheme cs) {
    final features = [
      ('Multi-language', 'Python, Java, C++, JS, Dart & more', Icons.code_rounded),
      ('Run Locally', 'Execute code offline on your device', Icons.play_circle_outline_rounded),
      ('Git & GitHub', 'Clone, commit, push, pull', Icons.account_tree_outlined),
      ('File Explorer', 'Manage projects & folders', Icons.folder_open_rounded),
      ('Terminal', 'Built-in xterm terminal', Icons.terminal_rounded),
      ('Live Preview', 'Instant HTML/CSS/JS preview', Icons.preview_rounded),
      ('Extensions', 'Themes, languages, tools', Icons.extension_rounded),
      ('Templates', 'Quick-start boilerplates', Icons.description_outlined),
    ];

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 8),
          Text(
            'Everything you need',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            'A complete dev environment in your pocket.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: List.generate(features.length, (i) {
                  final feature = features[i];
                  final delay = i * 0.08;
                  final anim = CurvedAnimation(
                    parent: _featuresAnim,
                    curve: Interval(
                      delay.clamp(0.0, 0.7),
                      (delay + 0.4).clamp(0.0, 1.0),
                      curve: Curves.easeOut,
                    ),
                  );
                  return FadeTransition(
                    opacity: anim,
                    child: SlideTransition(
                      position: Tween<Offset>(
                              begin: const Offset(0, 0.3), end: Offset.zero)
                          .animate(anim),
                      child: Container(
                        width: MediaQuery.of(context).size.width * 0.4,
                        constraints: const BoxConstraints(minHeight: 110),
                        child: Card(
                          elevation: 0,
                          color: cs.surfaceContainerHighest,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(feature.$3, size: 28, color: cs.primary),
                                const SizedBox(height: 8),
                                Text(
                                  feature.$1,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700, fontSize: 13),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  feature.$2,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontSize: 10,
                                      color: cs.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _navRow(),
          const SizedBox(height: 12),
          _buildDots(cs),
        ],
      ),
    );
  }

  Widget _buildLanguagePicker(ColorScheme cs) {
    const languages = [
      'python', 'javascript', 'typescript', 'java', 'cpp',
      'dart', 'html', 'css', 'rust', 'go', 'kotlin', 'swift',
      'php', 'ruby', 'csharp', 'bash',
    ];
    const popular = {'python', 'javascript', 'java', 'dart', 'typescript'};
    const subtitles = <String, String>{
      'python': 'Snippets + Run config',
      'javascript': 'Snippets + Node.js',
      'typescript': 'Snippets + Node.js',
      'java': 'Snippets + Compiler',
      'dart': 'Snippets + Flutter',
      'html': 'Snippets + Preview',
      'css': 'Snippets + Preview',
      'cpp': 'Snippets + GCC',
      'rust': 'Snippets + Cargo',
      'go': 'Snippets + Go run',
      'kotlin': 'Snippets + Compiler',
      'swift': 'Snippets + Compiler',
      'php': 'Snippets + PHP CLI',
      'ruby': 'Snippets + Ruby',
      'csharp': 'Snippets + .NET',
      'bash': 'Snippets + Shell',
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FadeTransition(
            opacity: _langAnim,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your primary languages',
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  'Pick languages to get custom snippets & run configs.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                ),
              ],

            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: List.generate(languages.length, (i) {
                  final lang = languages[i];
                  final isSelected = _selectedLanguages.contains(lang);
                  final isPopular = popular.contains(lang);
                  final subtitle = subtitles[lang] ?? 'Snippets + Run config';

                  final delay = (i * 0.05).clamp(0.0, 0.6);
                  final anim = CurvedAnimation(
                    parent: _langAnim,
                    curve: Interval(delay, (delay + 0.4).clamp(0.0, 1.0),
                        curve: Curves.easeOut),
                  );

                  return FadeTransition(
                    opacity: anim,
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          if (isSelected) {
                            _selectedLanguages.remove(lang);
                          } else {
                            _selectedLanguages.add(lang);
                          }
                        });
                        sl<SettingsStore>().primaryLanguages =
                            _selectedLanguages.toList();
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOut,
                        width: (MediaQuery.of(context).size.width - 40 - 8) / 2,
                        constraints: const BoxConstraints(minHeight: 110),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          color: isSelected
                              ? cs.primaryContainer
                              : cs.surfaceContainerHighest,
                          border: Border.all(
                            color: isSelected
                                ? cs.primary
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        padding: const EdgeInsets.all(6),
                        child: Stack(
                          children: [
                            Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    _iconForLanguage(lang),
                                    size: 26,
                                    color: isSelected
                                        ? cs.primary
                                        : cs.onSurfaceVariant,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    _languageDisplayName(lang),
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                      color: isSelected
                                          ? cs.onPrimaryContainer
                                          : cs.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    subtitle,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: isSelected
                                          ? cs.primary
                                          : cs.onSurfaceVariant.withValues(alpha: 0.7),
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            if (isPopular)
                              Positioned(
                                top: 0,
                                right: 0,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 4, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: cs.tertiary,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '★',
                                    style: TextStyle(
                                        fontSize: 9,
                                        color: cs.onTertiary,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                            if (isSelected)
                              Positioned(
                                top: 0,
                                left: 0,
                                child: Icon(Icons.check_circle,
                                    size: 16, color: cs.primary),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _navRow(),
          const SizedBox(height: 10),
          _buildDots(cs),
        ],
      ),
    );
  }


  Widget _buildStorage(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Icon(Icons.folder_special_rounded, size: 64, color: cs.primary),
          const SizedBox(height: 20),
          Text(
            'Workspace Location',
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          Text(
            'Projects are stored in the app\'s private folder by default. '
            'Pick a custom folder to access files from other apps.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
          ),
          Card(
            elevation: 0,
            color: cs.surfaceContainerHighest,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            child: ListTile(
              leading: Icon(Icons.folder_zip_outlined, color: cs.primary),
              title: const Text('Extract ZIP Project'),
              subtitle: const Text(
                'Unzip a GitHub download directly into workspace',
                style: TextStyle(fontSize: 12),
              ),
              trailing:
                  Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
              onTap: _extractZip,
            ),
          ),
          const Spacer(),
          _navRow(),
          const SizedBox(height: 12),
          _buildDots(cs),
        ],
      ),
    );
  }

  Widget _buildGitHub(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.account_circle_outlined, size: 72, color: cs.primary),
          const SizedBox(height: 20),
          Text(
            'Connect GitHub',
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            'Clone repos, push changes, and collaborate directly from your phone. You can skip and do this later.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 32),
          if (!_githubDone && !_connecting)
            FilledButton.icon(
              onPressed: _connectGitHub,
              icon: const Icon(Icons.login),
              label: const Text('Connect with GitHub'),
            ),
          if (_connecting) ...[
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(_status, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              'A browser tab will open.\nEnter the code shown here.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ],
          if (_githubDone) ...[
            Icon(Icons.check_circle_rounded, size: 52, color: cs.primary),
            const SizedBox(height: 8),
            Text('Connected!',
                style: TextStyle(
                    color: cs.primary, fontWeight: FontWeight.w700)),
          ],
          if (_status.isNotEmpty && !_connecting && !_githubDone)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(_status,
                  style: TextStyle(color: cs.error),
                  textAlign: TextAlign.center),
            ),
          const Spacer(),
          _navRow(),
          const SizedBox(height: 12),
          _buildDots(cs),
        ],
      ),
    );
  }

  Widget _buildRunCode(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.play_circle_outline_rounded,
              size: 72, color: cs.primary),
          const SizedBox(height: 20),
          Text(
            'Run Code Locally',
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          Text(
            'B Code runs Python, Java, C, C++, JavaScript, Dart, and more.\n'
            'Download runtimes from Extensions → Downloads to get started.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                  height: 1.5,
                ),
          ),
          const SizedBox(height: 24),
          Card(
            elevation: 0,
            color: cs.surfaceContainerHighest,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.offline_bolt_outlined,
                      size: 22, color: cs.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'No server needed — code runs 100% offline on your device.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          FilledButton.icon(
            onPressed: () {
              if (_selectedLanguages.isEmpty) {
                _finish();
              } else {
                _next();
              }
            },
            icon: const Icon(Icons.rocket_launch_rounded),
            label: const Text('Start Coding'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(200, 52),
              textStyle: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 12),
          _buildDots(cs),
        ],
      ),
    );
  }

  String _languageDisplayName(String id) {
    switch (id) {
      case 'dart':
        return 'Dart / Flutter';
      case 'typescript':
        return 'TypeScript';
      case 'javascript':
        return 'JavaScript';
      case 'python':
        return 'Python';
      case 'java':
        return 'Java';
      case 'cpp':
        return 'C++';
      case 'c':
        return 'C';
      case 'html':
        return 'HTML';
      case 'css':
        return 'CSS';
      default:
        return id.toUpperCase();
    }
  }

  String? _runtimeForLanguage(String lang) {
    switch (lang) {
      case 'python': return 'cpython';
      case 'java': return 'openjdk';
      case 'cpp': return 'clang';
      case 'c': return 'clang';
      case 'javascript': return 'nodejs';
      case 'typescript': return 'nodejs';
      case 'bash': return 'bash';
      default: return null;
    }
  }

  void _startSetup() {
    final dl = sl<RuntimeDownloadService>();
    final toDownload = <String>{};
    for (final lang in _selectedLanguages) {
      final runtimeId = _runtimeForLanguage(lang);
      if (runtimeId != null) {
        toDownload.add(runtimeId);
      }
    }
    
    if (toDownload.isEmpty) {
      _finish();
      return;
    }

    for (final id in toDownload) {
      dl.download(id);
    }
  }

  Widget _buildSetupEnvironment(ColorScheme cs) {
    final dl = sl<RuntimeDownloadService>();
    final runtimes = _selectedLanguages
        .map(_runtimeForLanguage)
        .whereType<String>()
        .toSet()
        .toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Spacer(),
          Icon(Icons.settings_suggest_rounded, size: 84, color: cs.primary),
          const SizedBox(height: 24),
          Text(
            'Setting up environments',
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          Text(
            'Downloading and installing runtime tools for your selected languages. This might take a moment depending on your network.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                  height: 1.5,
                ),
          ),
          const SizedBox(height: 32),
          Expanded(
            flex: 3,
            child: AnimatedBuilder(
              animation: dl,
              builder: (context, _) {
                int complete = 0;
                for (final id in runtimes) {
                  final state = dl.stateFor(id);
                  if (state.phase == RuntimeDownloadPhase.installed || 
                      state.phase == RuntimeDownloadPhase.failed) {
                    complete++;
                  }
                }
                
                if (complete == runtimes.length && runtimes.isNotEmpty) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && _step == 6) {
                      _finish();
                    }
                  });
                }

                return ListView.builder(
                  physics: const BouncingScrollPhysics(),
                  itemCount: runtimes.length,
                  itemBuilder: (ctx, i) {
                    final id = runtimes[i];
                    final spec = specForRuntime(id);
                    final state = dl.stateFor(id);
                    final progress = state.progress ?? 0.0;
                    final isDone = state.phase == RuntimeDownloadPhase.installed;
                    final isFailed = state.phase == RuntimeDownloadPhase.failed;

                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: isDone 
                            ? cs.primaryContainer.withValues(alpha: 0.4)
                            : cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isDone 
                              ? cs.primary.withValues(alpha: 0.5) 
                              : Colors.transparent,
                          width: 1,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    spec?.title ?? id,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                  ),
                                ),
                                if (isDone)
                                  Icon(Icons.check_circle_rounded, color: cs.primary, size: 24)
                                else if (isFailed)
                                  Icon(Icons.error_rounded, color: cs.error, size: 24)
                                else
                                  Text(
                                    '${(progress * 100).toInt()}%',
                                    style: TextStyle(
                                      color: cs.primary, 
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                              ],
                            ),
                            if (!isDone && !isFailed) ...[
                              const SizedBox(height: 16),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: LinearProgressIndicator(
                                  value: progress > 0 ? progress : null,
                                  minHeight: 8,
                                  backgroundColor: cs.surfaceContainerHigh,
                                ),
                              ),
                              if (state.currentPackage.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  'Downloading: ${state.currentPackage}',
                                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ],
                            if (isFailed) ...[
                              const SizedBox(height: 8),
                              Text(
                                state.error ?? 'Failed',
                                style: TextStyle(fontSize: 13, color: cs.error),
                              ),
                            ]
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: cs.errorContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: cs.error, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Please do not close the app or page while we set up your environment.',
                    style: TextStyle(color: cs.error, fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: _finish,
            child: const Text('Skip / Continue Anyway'),
          ),
          const SizedBox(height: 12),
          _buildDots(cs),
        ],
      ),
    );
  }

  IconData _iconForLanguage(String languageId) {
    switch (languageId) {
      case 'dart':
        return Icons.flutter_dash;
      case 'typescript':
      case 'javascript':
        return Icons.javascript_rounded;
      case 'html':
        return Icons.html_rounded;
      case 'python':
        return Icons.terminal_rounded;
      case 'java':
        return Icons.coffee_rounded;
      case 'cpp':
      case 'c':
        return Icons.memory_rounded;
      case 'css':
        return Icons.css_rounded;
      default:
        return Icons.code_rounded;
    }
  }
}