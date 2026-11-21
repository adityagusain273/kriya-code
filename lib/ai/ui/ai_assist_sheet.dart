import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/di.dart';
import '../../core/haptics.dart';
import '../../monetization/entitlement_service.dart';
import '../../monetization/pro_paywall_sheet.dart';
import '../ai_service.dart';
import '../kriya_ai_context.dart';

class AiAssistSheet extends StatefulWidget {
  final String? initialCode;
  final String? contextDescription;
  final String? workspaceFolder;
  final List<String>? diagnosticsSummary;
  final String? defaultPrompt;
  final void Function(String replacement)? onInsert;
  final void Function(String replacement)? onApplyCode;

  const AiAssistSheet({
    super.key,
    this.initialCode,
    this.contextDescription,
    this.workspaceFolder,
    this.diagnosticsSummary,
    this.defaultPrompt,
    this.onInsert,
    this.onApplyCode,
  });

  static Future<void> show(
    BuildContext context, {
    String? initialCode,
    String? contextDescription,
    String? workspaceFolder,
    List<String>? diagnosticsSummary,
    String? defaultPrompt,
    void Function(String replacement)? onInsert,
    void Function(String replacement)? onApplyCode,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => AiAssistSheet(
        initialCode: initialCode,
        contextDescription: contextDescription,
        workspaceFolder: workspaceFolder,
        diagnosticsSummary: diagnosticsSummary,
        defaultPrompt: defaultPrompt,
        onInsert: onInsert,
        onApplyCode: onApplyCode,
      ),
    );
  }

  @override
  State<AiAssistSheet> createState() => _AiAssistSheetState();
}

class _AiAssistSheetState extends State<AiAssistSheet> {
  final TextEditingController _promptController = TextEditingController();
  final TextEditingController _apiKeyController = TextEditingController();

  bool _loading = false;
  bool _codeApplied = false;
  String? _response;
  String? _error;
  String? _configuredKey;
  AiProvider _detectedProvider = AiProvider.unknown;
  bool _validatingKey = false;
  String? _verifiedModel;

  String? _extractCodeBlock(String response) {
    final match = RegExp(r'```(?:\w+)?\s*\n([\s\S]*?)\n```', multiLine: true).firstMatch(response);
    if (match != null && match.group(1) != null) {
      return match.group(1)!.trim();
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    if (widget.defaultPrompt != null && widget.defaultPrompt!.isNotEmpty) {
      _promptController.text = widget.defaultPrompt!;
    }
    _checkKey();
  }

  @override
  void dispose() {
    _promptController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _checkKey() async {
    if (!sl.isRegistered<AiService>()) return;
    final ai = sl<AiService>();
    final key = await ai.getApiKey();
    if (mounted) {
      String? model;
      final provider = (key != null && key.isNotEmpty) ? detectAiProvider(key) : AiProvider.unknown;
      if (provider == AiProvider.gemini && key != null) {
        try {
          model = await ai.resolveActiveGeminiModel(key);
        } catch (_) {}
      }
      setState(() {
        _configuredKey = key;
        _detectedProvider = provider;
        _verifiedModel = model;
      });
      if (key != null && widget.defaultPrompt != null && widget.defaultPrompt!.isNotEmpty) {
        _executePrompt(widget.defaultPrompt!);
      }
    }
  }

  bool _isProUser() {
    if (!sl.isRegistered<EntitlementService>()) return false;
    return sl<EntitlementService>().isRuntimeUnlocked('');
  }

  Future<void> _saveApiKey() async {
    final clean = _apiKeyController.text.trim();
    if (clean.isEmpty) return;
    Haptics.light();

    setState(() {
      _validatingKey = true;
      _error = null;
    });

    final ai = sl<AiService>();
    final detected = detectAiProvider(clean);

    try {
      String? supportedModel;
      if (detected == AiProvider.gemini) {
        supportedModel = await ai.verifyAndResolveActiveGeminiModel(clean);
      }

      await ai.setApiKey(clean);
      if (supportedModel != null) {
        await ai.setActiveGeminiModel(supportedModel);
      }

      if (mounted) {
        setState(() {
          _configuredKey = clean;
          _detectedProvider = detected;
          _verifiedModel = supportedModel;
          _apiKeyController.clear();
          _validatingKey = false;
          _error = null;
        });
        if (widget.defaultPrompt != null && widget.defaultPrompt!.isNotEmpty) {
          _executePrompt(widget.defaultPrompt!);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _validatingKey = false;
          _error = 'Model support check failed: $e';
        });
      }
    }
  }

  Future<void> _executePrompt(String promptText) async {
    final cleanPrompt = promptText.trim();
    if (cleanPrompt.isEmpty) return;
    Haptics.light();

    final isPro = _isProUser();
    final ai = sl<AiService>();

    if (!ai.canRequest(isPro)) {
      if (mounted) {
        final boughtPro = await showProPaywallSheet(context);
        if (boughtPro && mounted) {
          _executePrompt(promptText);
        }
      }
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _response = null;
      _codeApplied = false;
    });

    final fullPrompt = StringBuffer();
    if (widget.workspaceFolder != null && widget.workspaceFolder!.isNotEmpty) {
      fullPrompt.writeln('Workspace Folder: ${widget.workspaceFolder}');
    }
    if (widget.contextDescription != null && widget.contextDescription!.isNotEmpty) {
      fullPrompt.writeln('File: ${widget.contextDescription}');
    }
    if (widget.diagnosticsSummary != null && widget.diagnosticsSummary!.isNotEmpty) {
      fullPrompt.writeln('Current Syntax/Runtime Diagnostics:');
      for (final d in widget.diagnosticsSummary!) {
        fullPrompt.writeln('- $d');
      }
    }
    if (widget.initialCode != null && widget.initialCode!.isNotEmpty) {
      fullPrompt.writeln('Code:\n```\n${widget.initialCode}\n```\n');
    }
    fullPrompt.writeln(cleanPrompt);

    final lang = KriyaAiContext.inferLanguage(widget.contextDescription);
    final systemPrompt = KriyaAiContext.buildSystemPrompt(
      filePath: widget.contextDescription,
      languageId: lang != 'text' ? lang : null,
      workspaceFolder: widget.workspaceFolder,
      diagnosticsSummary: widget.diagnosticsSummary,
    );

    try {
      final res = await ai.complete(
        prompt: fullPrompt.toString(),
        systemPrompt: systemPrompt,
        isPro: isPro,
      );
      if (mounted) {
        String? activeModel = _verifiedModel;
        if (_detectedProvider == AiProvider.gemini && _configuredKey != null) {
          try {
            activeModel = await ai.resolveActiveGeminiModel(_configuredKey!);
          } catch (_) {}
        }
        setState(() {
          _response = res;
          _loading = false;
          _verifiedModel = activeModel;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Widget _buildKeySetup(ThemeData theme) {
    final previewProvider = detectAiProvider(_apiKeyController.text);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF161B22),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF30363D)),
            ),
            child: Row(
              children: [
                const Icon(Icons.key_rounded, color: Color(0xFF00E676), size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Paste your AI API key once to activate. Supports Gemini, Groq, OpenAI, Claude, OpenRouter, and GitHub Models.',
                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _apiKeyController,
            style: const TextStyle(color: Colors.white, fontSize: 13, fontFamily: 'monospace'),
            decoration: InputDecoration(
              hintText: 'Paste key (AIzaSy..., gsk_..., sk-...)',
              hintStyle: const TextStyle(color: Colors.white30, fontSize: 12),
              filled: true,
              fillColor: const Color(0xFF0D1117),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFF30363D)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFF00E676)),
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (_apiKeyController.text.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.bolt, color: Color(0xFF00E676), size: 14),
                const SizedBox(width: 4),
                Text(
                  previewProvider != AiProvider.unknown
                      ? 'Detected: ${previewProvider.displayName} (${previewProvider.description})'
                      : 'Unrecognized prefix (will use standard OpenAI format)',
                  style: const TextStyle(color: Color(0xFF00E676), fontSize: 11),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.open_in_new, size: 14),
                  label: const Text('Get Free Gemini Key', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF4FC3F7),
                    side: const BorderSide(color: Color(0xFF4FC3F7)),
                  ),
                  onPressed: () => launchUrl(
                    Uri.parse('https://aistudio.google.com/app/apikey'),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF00E676),
                  foregroundColor: Colors.black,
                ),
                onPressed: (_apiKeyController.text.trim().isEmpty || _validatingKey) ? null : _saveApiKey,
                child: _validatingKey
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                      )
                    : const Text('Save Key', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuotaBadge() {
    final isPro = _isProUser();
    if (isPro) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFF00E676).withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Text(
          '⚡ PRO UNLIMITED',
          style: TextStyle(color: Color(0xFF00E676), fontSize: 10, fontWeight: FontWeight.bold),
        ),
      );
    }

    final remaining = sl<AiService>().getRemainingQuotaToday(false);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF21262D),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        'Free: $remaining/3 left today',
        style: TextStyle(
          color: remaining > 0 ? const Color(0xFF4FC3F7) : Colors.amber,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);

    return Container(
      constraints: BoxConstraints(
        maxHeight: media.size.height * 0.88,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF10141D),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(color: const Color(0xFF263342)),
      ),
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                margin: const EdgeInsets.only(top: 8, bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.auto_awesome, color: Color(0xFF00E676), size: 16),
                            const SizedBox(width: 6),
                            const Flexible(
                              child: Text(
                                'Kriya AI Assistant',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                            ),
                          ],
                        ),
                        if (_configuredKey != null && _detectedProvider != AiProvider.unknown)
                          Padding(
                            padding: const EdgeInsets.only(top: 2, left: 22),
                            child: Text(
                              _verifiedModel != null
                                  ? '${_detectedProvider.displayName} • $_verifiedModel'
                                  : _detectedProvider.displayName,
                              style: const TextStyle(
                                color: Color(0xFF00E676),
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (_configuredKey != null) ...[
                    _buildQuotaBadge(),
                    const SizedBox(width: 8),
                  ],
                  IconButton(
                    icon: const Icon(Icons.close, size: 18, color: Colors.white60),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFF263342)),
            if (_configuredKey == null)
              _buildKeySetup(theme)
            else
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (widget.initialCode != null && widget.initialCode!.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF161B22),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFF30363D)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.code, size: 14, color: Colors.white60),
                                  const SizedBox(width: 6),
                                  Text(
                                    widget.contextDescription ?? 'Selected Code',
                                    style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                widget.initialCode!.length > 300
                                    ? '${widget.initialCode!.substring(0, 300)}…'
                                    : widget.initialCode!,
                                maxLines: 4,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white54, fontSize: 11, fontFamily: 'monospace'),
                              ),
                            ],
                          ),
                        ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          ActionChip(
                            label: const Text('Explain Code', style: TextStyle(fontSize: 11)),
                            avatar: const Icon(Icons.help_outline, size: 14),
                            onPressed: () => _executePrompt('Explain what this code does clearly and concisely.'),
                          ),
                          ActionChip(
                            label: const Text('Find & Fix Bugs', style: TextStyle(fontSize: 11)),
                            avatar: const Icon(Icons.bug_report_outlined, size: 14),
                            onPressed: () => _executePrompt('Analyze this code for bugs or edge cases and show the corrected code.'),
                          ),
                          ActionChip(
                            label: const Text('Add Comments', style: TextStyle(fontSize: 11)),
                            avatar: const Icon(Icons.comment_outlined, size: 14),
                            onPressed: () => _executePrompt('Add clear, helpful comments to this code without changing its logic.'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _promptController,
                              style: const TextStyle(color: Colors.white, fontSize: 13),
                              decoration: InputDecoration(
                                hintText: 'Ask Kriya AI anything...',
                                hintStyle: const TextStyle(color: Colors.white30, fontSize: 12),
                                filled: true,
                                fillColor: const Color(0xFF161B22),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: const BorderSide(color: Color(0xFF30363D)),
                                ),
                              ),
                              onSubmitted: _executePrompt,
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filled(
                            style: IconButton.styleFrom(
                              backgroundColor: const Color(0xFF00E676),
                              foregroundColor: Colors.black,
                            ),
                            icon: const Icon(Icons.send_rounded, size: 16),
                            onPressed: _loading ? null : () => _executePrompt(_promptController.text),
                          ),
                        ],
                      ),
                      if (_loading) ...[
                        const SizedBox(height: 24),
                        const Center(
                          child: Column(
                            children: [
                              SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFF00E676)),
                              ),
                              SizedBox(height: 8),
                              Text('Thinking…', style: TextStyle(color: Colors.white60, fontSize: 12)),
                            ],
                          ),
                        ),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
                          ),
                          child: Text(
                            _error!,
                            style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                          ),
                        ),
                      ],
                      if (_response != null) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF161B22),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFF30363D)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SelectableText(
                                _response!,
                                style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.4),
                              ),
                              if (_codeApplied) ...[
                                const SizedBox(height: 10),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF00E676).withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: const Color(0xFF00E676).withValues(alpha: 0.5)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.check_circle_rounded, size: 14, color: Color(0xFF00E676)),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Applied changes to ${widget.contextDescription ?? "editor"} in real-time!',
                                        style: const TextStyle(color: Color(0xFF00E676), fontSize: 11, fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              const SizedBox(height: 12),
                              Wrap(
                                alignment: WrapAlignment.end,
                                spacing: 8,
                                runSpacing: 6,
                                children: [
                                  TextButton.icon(
                                    icon: const Icon(Icons.copy_rounded, size: 14),
                                    label: const Text('Copy'),
                                    onPressed: () {
                                      Haptics.light();
                                      Clipboard.setData(ClipboardData(text: _response!));
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Copied to clipboard')),
                                      );
                                    },
                                  ),
                                  if (widget.onApplyCode != null) ...[
                                    FilledButton.icon(
                                      style: FilledButton.styleFrom(
                                        backgroundColor: const Color(0xFF00E676),
                                        foregroundColor: Colors.black,
                                      ),
                                      icon: const Icon(Icons.bolt_rounded, size: 16),
                                      label: const Text('Apply to Editor (Real-time)', style: TextStyle(fontWeight: FontWeight.bold)),
                                      onPressed: () {
                                        Haptics.medium();
                                        final code = _extractCodeBlock(_response!) ?? _response!;
                                        widget.onApplyCode!(code);
                                        setState(() {
                                          _codeApplied = true;
                                        });
                                      },
                                    ),
                                  ] else if (widget.onInsert != null) ...[
                                    FilledButton.icon(
                                      style: FilledButton.styleFrom(
                                        backgroundColor: const Color(0xFF00E676),
                                        foregroundColor: Colors.black,
                                      ),
                                      icon: const Icon(Icons.input_rounded, size: 14),
                                      label: const Text('Insert Code'),
                                      onPressed: () {
                                        final code = _extractCodeBlock(_response!) ?? _response!;
                                        widget.onInsert!(code);
                                        Navigator.of(context).pop();
                                      },
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
