import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';

import '../core/crash_reporter.dart';
import '../editor/highlighting/syntax_themes.dart';
import '../execution/termux_runner.dart';
import 'settings_store.dart';

class SettingsPage extends StatefulWidget {
  final SettingsStore store;

  const SettingsPage({super.key, required this.store});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late double _fontSize = widget.store.fontSize.toDouble();
  late int _tabSize = widget.store.tabSize;
  late ThemeMode _themeMode = widget.store.themeMode;
  late bool _autoSave = widget.store.autoSave;
  late int _autoSaveDelay = widget.store.autoSaveDelayMs;
  late String _syntaxThemeId = widget.store.syntaxThemeId;
  late bool _wordWrap = widget.store.wordWrap;
  late bool _showLineNumbers = widget.store.showLineNumbers;
  late String _fontFamily = widget.store.fontFamily;
  bool _termuxInstalled = false;
  bool _termuxChecking = true;

  @override
  void initState() {
    super.initState();
    _checkTermux();
  }

  Future<void> _checkTermux() async {
    final installed = await TermuxRunner.isInstalled();
    if (mounted) {
      setState(() {
        _termuxInstalled = installed;
        _termuxChecking = false;
      });
    }
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, top: 20, bottom: 4),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _sectionHeader('Editor'),
          ListTile(
            title: const Text('Font size'),
            subtitle: Row(
              children: [
                const Icon(Icons.text_fields, size: 14),
                Expanded(
                  child: Slider(
                    min: 10,
                    max: 24,
                    divisions: 14,
                    label: _fontSize.round().toString(),
                    value: _fontSize,
                    onChanged: (v) {
                      setState(() => _fontSize = v);
                      widget.store.fontSize = v;
                    },
                  ),
                ),
                Text(_fontSize.round().toString(), style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
          ListTile(
            title: const Text('Font family'),
            trailing: DropdownButton<String>(
              value: _fontFamily,
              underline: const SizedBox(),
              items: const [
                DropdownMenuItem(value: 'monospace', child: Text('System Mono')),
                DropdownMenuItem(value: 'Courier New', child: Text('Courier New')),
                DropdownMenuItem(value: 'Roboto Mono', child: Text('Roboto Mono')),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() => _fontFamily = v);
                widget.store.fontFamily = v;
              },
            ),
          ),
          ListTile(
            title: const Text('Tab size'),
            trailing: SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 2, label: Text('2')),
                ButtonSegment(value: 4, label: Text('4')),
                ButtonSegment(value: 8, label: Text('8')),
              ],
              selected: {_tabSize},
              onSelectionChanged: (s) {
                setState(() => _tabSize = s.first);
                widget.store.tabSize = s.first;
              },
            ),
          ),
          SwitchListTile(
            title: const Text('Word wrap'),
            subtitle: const Text('Wrap long lines to fit the screen'),
            value: _wordWrap,
            onChanged: (v) {
              setState(() => _wordWrap = v);
              widget.store.wordWrap = v;
            },
          ),
          SwitchListTile(
            title: const Text('Show line numbers'),
            value: _showLineNumbers,
            onChanged: (v) {
              setState(() => _showLineNumbers = v);
              widget.store.showLineNumbers = v;
            },
          ),
          const Divider(height: 8),
          _sectionHeader('Auto-save'),
          SwitchListTile(
            title: const Text('Auto-save'),
            subtitle: const Text('Save files automatically after changes'),
            value: _autoSave,
            onChanged: (v) {
              setState(() => _autoSave = v);
              widget.store.autoSave = v;
            },
          ),
          if (_autoSave)
            ListTile(
              title: const Text('Auto-save delay'),
              subtitle: Slider(
                min: 500,
                max: 5000,
                divisions: 9,
                label: '${(_autoSaveDelay / 1000).toStringAsFixed(1)}s',
                value: _autoSaveDelay.toDouble(),
                onChanged: (v) {
                  setState(() => _autoSaveDelay = v.round());
                  widget.store.autoSaveDelayMs = v.round();
                },
              ),
            ),
          const Divider(height: 8),
          _sectionHeader('Appearance'),
          RadioGroup<ThemeMode>(
            groupValue: _themeMode,
            onChanged: (mode) => _setTheme(mode!),
            child: Column(
              children: [
                RadioListTile<ThemeMode>(
                  title: const Text('System default'),
                  value: ThemeMode.system,
                ),
                RadioListTile<ThemeMode>(
                  title: const Text('Light'),
                  value: ThemeMode.light,
                ),
                RadioListTile<ThemeMode>(
                  title: const Text('Dark'),
                  value: ThemeMode.dark,
                ),
              ],
            ),
          ),
          const Divider(height: 8),
          _sectionHeader('Syntax Theme'),
          RadioGroup<String>(
            groupValue: _syntaxThemeId,
            onChanged: (v) {
              if (v == null) return;
              setState(() => _syntaxThemeId = v);
              widget.store.syntaxThemeId = v;
            },
            child: Column(
              children: SyntaxThemes.all.map((theme) => RadioListTile<String>(
                title: Text(theme.name),
                value: theme.id,
              )).toList(),
            ),
          ),
          const Divider(height: 8),
          _sectionHeader('Privacy'),
          SwitchListTile(
            title: const Text('Send crash reports'),
            subtitle: const Text('Help fix crashes by sending anonymous device info'),
            value: widget.store.crashReportingEnabled,
            onChanged: (v) {
              setState(() => widget.store.crashReportingEnabled = v);
              CrashReporter.setCollectionEnabled(v);
            },
          ),
          const Divider(height: 8),
          _sectionHeader('Git Identity'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              'Used as the author on all commits.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          ListTile(
            title: const Text('Name'),
            subtitle: TextFormField(
              initialValue: widget.store.gitName,
              decoration: const InputDecoration(hintText: 'Your Name', isDense: true),
              onChanged: (v) => widget.store.gitName = v,
            ),
          ),
          ListTile(
            title: const Text('Email'),
            subtitle: TextFormField(
              initialValue: widget.store.gitEmail,
              decoration: const InputDecoration(hintText: 'you@example.com', isDense: true),
              keyboardType: TextInputType.emailAddress,
              onChanged: (v) => widget.store.gitEmail = v,
            ),
          ),
          const Divider(height: 8),
          _sectionHeader('Termux Integration'),
          if (_termuxChecking)
            const ListTile(
              leading: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              title: Text('Checking Termux...'),
            )
          else if (_termuxInstalled)
            ListTile(
              leading: const Icon(Icons.check_circle, color: Colors.green),
              title: const Text('Termux detected'),
              subtitle: const Text('Terminal and code execution use Termux runtimes'),
            )
          else
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Termux not installed'),
              subtitle: const Text('Install Termux for more runtimes (Python, Node, GCC)'),
              trailing: FilledButton.tonal(
                onPressed: () => _showTermuxSetupDialog(context),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('Setup'),
              ),
            ),
          const Divider(height: 8),
          _sectionHeader('About'),
          const ListTile(title: Text('B Code'), subtitle: Text('Version 1.0.0 · com.bcode.editor')),
          ListTile(
            leading: const Icon(Icons.bug_report_outlined),
            title: const Text('Report a Bug'),
            subtitle: const Text('Send crash logs and device info'),
            onTap: () => _showBugReportDialog(context),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  void _setTheme(ThemeMode mode) {
    setState(() => _themeMode = mode);
    widget.store.themeMode = mode;
  }

  Future<void> _showBugReportDialog(BuildContext context) async {
    final controller = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);
    final List<String> attachedScreenshots = [];

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Report a Bug / Feedback'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Describe what went wrong or send us feedback. Crash logs and device info will be attached automatically.',
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      hintText: 'What happened?',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Attachments', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 8),
                  if (attachedScreenshots.isNotEmpty)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: attachedScreenshots.map((file) {
                        return Chip(
                          label: Text(file, style: const TextStyle(fontSize: 12)),
                          onDeleted: () {
                            setState(() => attachedScreenshots.remove(file));
                          },
                          deleteIcon: const Icon(Icons.close, size: 16),
                        );
                      }).toList(),
                    ),
                  if (attachedScreenshots.isNotEmpty) const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final picker = ImagePicker();
                      final XFile? image = await picker.pickImage(source: ImageSource.gallery);
                      if (image != null) {
                        setState(() {
                          attachedScreenshots.add(image.name);
                        });
                      }
                    },
                    icon: const Icon(Icons.add_photo_alternate, size: 16),
                    label: const Text('Attach Screenshot'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(ctx, true),
                icon: const Icon(Icons.send, size: 16),
                label: const Text('Submit'),
              ),
            ],
          );
        }
      ),
    );

    if (confirmed == true && mounted) {
      await CrashReporter.submitBugReport(userMessage: controller.text);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Feedback submitted with ${attachedScreenshots.length} screenshots. Thank you!'),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _showTermuxSetupDialog(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Setup Termux'),
        content: const SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '1. Install Termux from F-Droid (recommended) or Google Play',
                style: TextStyle(fontSize: 13),
              ),
              SizedBox(height: 8),
              Text(
                '2. Open Termux and install packages:',
                style: TextStyle(fontSize: 13),
              ),
              SizedBox(height: 4),
              Text(
                '   pkg install python nodejs gcc clang',
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  backgroundColor: Color(0xFF1E1E1E),
                ),
              ),
              SizedBox(height: 8),
              Text(
                '3. In Termux, go to Settings → Enable "Allow external apps"',
                style: TextStyle(fontSize: 13),
              ),
              SizedBox(height: 8),
              Text(
                '4. B Code will automatically detect Termux on next launch',
                style: TextStyle(fontSize: 13),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              launchUrl(Uri.parse('https://f-droid.org/en/packages/com.termux/'));
            },
            child: const Text('Get Termux'),
          ),
        ],
      ),
    );
  }
}
