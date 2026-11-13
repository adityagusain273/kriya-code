
import 'package:flutter/material.dart';

import '../core/di.dart';
import '../workspace/fs_service.dart';
import '../editor/tab_manager.dart';
import '../editor/editor_page.dart';
import '../settings/settings_store.dart';
import '../execution/runtime_catalog.dart';
import '../execution/runtime_download_service.dart';

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
  late final AnimationController _langAnim =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 600));

  final Set<String> _selectedLanguages = {};
  bool _createStarterExample = true;

  static const int _totalSteps = 2;

  RuntimeDownloadService get _downloads => sl<RuntimeDownloadService>();
  RuntimePreview? _pythonPreview;

  @override
  void initState() {
    super.initState();
    _downloads.addListener(_onDownloadChange);
    _loadPythonPreview();
  }

  void _onDownloadChange() {
    if (mounted) setState(() {});
  }

  Future<void> _loadPythonPreview() async {
    final preview = await _downloads.inspect('cpython');
    if (mounted) setState(() => _pythonPreview = preview);
  }

  @override
  void dispose() {
    _downloads.removeListener(_onDownloadChange);
    _pageCtrl.dispose();
    _welcomeAnim.dispose();
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
        _langAnim.forward(from: 0);
      default:
        break;
    }
  }

  void _skip() => _finish();

  void _finish() {
    sl<SettingsStore>().onboardingComplete = true;
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const EditorPage()),
    );
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
            _buildLanguagePicker(cs),
            _buildQuickStart(cs),
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

  Future<void> _createStarterFile() async {
    try {
      final fs = sl<FsService>();
      final isWeb = _selectedLanguages.contains('html') || _selectedLanguages.contains('javascript');
      final fileName = isWeb ? 'index.html' : 'main.py';
      final content = isWeb
          ? '<!DOCTYPE html>\n<html>\n<head>\n  <meta charset="utf-8">\n  <title>B Code</title>\n</head>\n<body>\n  <h1>Hello from B Code!</h1>\n  <p>Tap Preview in the top bar to view this live.</p>\n</body>\n</html>\n'
          : '# Welcome to B Code!\n# Tap the green Play button in the top bar to run this file.\n\ndef main():\n    print("Hello from B Code!")\n    print("Your mobile coding environment is ready.")\n\nif __name__ == "__main__":\n    main()\n';
      await fs.writeFile(fileName, content);
      await sl<TabManager>().open(fileName);
    } catch (_) {}
  }

  Widget _starterOptionCard({
    required ColorScheme cs,
    required bool selected,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: selected
              ? cs.primaryContainer.withValues(alpha: 0.35)
              : cs.surfaceContainerHighest.withValues(alpha: 0.5),
          border: Border.all(
            color: selected ? cs.primary : cs.outlineVariant.withValues(alpha: 0.5),
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 32, color: iconColor),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  const SizedBox(height: 3),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant.withValues(alpha: 0.85),
                          height: 1.25)),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_circle_rounded, color: cs.primary, size: 20),
          ],
        ),
      ),
    );
  }

  String _formatBytes(int bytes) {
    final mb = bytes / (1024 * 1024);
    if (mb >= 1) return '${mb.toStringAsFixed(1)} MB';
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }

  Widget _buildPythonRuntimeCard(ColorScheme cs) {
    final state = _downloads.stateFor('cpython');
    final installed = _downloads.isInstalled('cpython') ||
        state.phase == RuntimeDownloadPhase.installed;
    final spec = specForRuntime('cpython');
    final versionStr = _pythonPreview?.version ?? spec?.approxVersion ?? '3.14';
    final sizeStr = _pythonPreview != null
        ? _formatBytes(_pythonPreview!.sizeBytes)
        : '≈${spec?.defaultSizeMb ?? 10} MB';

    if (installed) {
      return Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: cs.primaryContainer.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.primary.withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            Icon(Icons.check_circle_rounded, color: cs.primary, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Python $versionStr runtime installed · Ready to run offline',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (state.phase == RuntimeDownloadPhase.resolving ||
        state.phase == RuntimeDownloadPhase.downloading ||
        state.phase == RuntimeDownloadPhase.installing) {
      return Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  state.phase == RuntimeDownloadPhase.installing
                      ? 'Installing Python runtime…'
                      : state.currentPackage.isNotEmpty
                          ? 'Downloading ${state.currentPackage}…'
                          : 'Preparing download…',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                TextButton(
                  onPressed: () => _downloads.cancel('cpython'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                  ),
                  child: const Text('Cancel', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: state.phase == RuntimeDownloadPhase.installing ? null : state.progress,
            ),
            if (state.totalBytes > 0) ...[
              const SizedBox(height: 4),
              Text(
                '${_formatBytes(state.receivedBytes)} of ${_formatBytes(state.totalBytes)}',
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              ),
            ],
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(Icons.terminal_rounded, size: 24, color: cs.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Download Python runtime ($sizeStr)',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
                Text(
                  'Python $versionStr to run code offline without Termux',
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                ),
                if (state.phase == RuntimeDownloadPhase.failed && state.error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      state.error!,
                      style: TextStyle(fontSize: 10, color: cs.error),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.tonal(
            onPressed: () => _downloads.download('cpython'),
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            ),
            child: Text(
              state.phase == RuntimeDownloadPhase.failed ? 'Retry' : 'Download',
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickStart(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
      child: Column(
        children: [
          const Spacer(),
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: cs.primaryContainer,
            ),
            child: Icon(Icons.rocket_launch_rounded, size: 38, color: cs.primary),
          ),
          const SizedBox(height: 20),
          Text(
            "You're ready to code!",
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'B Code is configured for you. Choose how you want to start:',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 24),
          _starterOptionCard(
            cs: cs,
            selected: _createStarterExample,
            icon: Icons.play_circle_filled_rounded,
            iconColor: const Color(0xFF4CAF50),
            title: 'Try a Starter Example',
            subtitle: 'Opens a working Hello World file ready to run with the top Play button',
            onTap: () => setState(() => _createStarterExample = true),
          ),
          if (_createStarterExample &&
              !(_selectedLanguages.contains('html') ||
                  _selectedLanguages.contains('javascript')))
            _buildPythonRuntimeCard(cs),
          const SizedBox(height: 12),
          _starterOptionCard(
            cs: cs,
            selected: !_createStarterExample,
            icon: Icons.note_add_outlined,
            iconColor: cs.primary,
            title: 'Blank Workspace',
            subtitle: 'Start with an empty workspace and create or import your own files',
            onTap: () => setState(() => _createStarterExample = false),
          ),
          const Spacer(),
          FilledButton.icon(
            onPressed: () async {
              if (_createStarterExample) {
                await _createStarterFile();
              }
              _finish();
            },
            icon: const Icon(Icons.arrow_forward_rounded),
            label: const Text('Start Coding'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 50),
              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
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