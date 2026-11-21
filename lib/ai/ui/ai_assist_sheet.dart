import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/di.dart';
import '../../core/haptics.dart';
import '../../editor/tab_manager.dart';
import '../../monetization/entitlement_service.dart';
import '../../monetization/pro_paywall_sheet.dart';
import '../../workspace/fs_service.dart';
import '../ai_service.dart';
import '../kriya_ai_context.dart';

class AiChatMessage {
  final String role; // 'user' or 'assistant'
  final String content;
  final DateTime timestamp;
  final bool isError;
  bool codeApplied;

  AiChatMessage({
    required this.role,
    required this.content,
    DateTime? timestamp,
    this.isError = false,
    this.codeApplied = false,
  }) : timestamp = timestamp ?? DateTime.now();
}

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
  final ScrollController _scrollController = ScrollController();

  final List<AiChatMessage> _messages = [];

  bool _loading = false;
  String? _error;
  String? _configuredKey;
  AiProvider _detectedProvider = AiProvider.unknown;
  bool _validatingKey = false;
  String? _verifiedModel;

  List<EditorTab> _openTabs = [];
  EditorTab? _selectedTab;
  String? _activeFilePath;
  String? _activeCode;
  String? _activeWorkspaceFolder;

  @override
  void initState() {
    super.initState();
    _initWorkspaceContext();
    _checkKey();
  }

  void _initWorkspaceContext() {
    if (sl.isRegistered<TabManager>()) {
      final tabMgr = sl<TabManager>();
      _openTabs = List.from(tabMgr.tabs);

      if (widget.contextDescription != null) {
        _selectedTab = _openTabs.cast<EditorTab?>().firstWhere(
          (t) =>
              t?.filePath == widget.contextDescription ||
              t?.name == widget.contextDescription ||
              (t?.filePath != null &&
                  widget.contextDescription != null &&
                  t!.filePath.endsWith(widget.contextDescription!)),
          orElse: () => null,
        );
      }
      _selectedTab ??= tabMgr.active ?? (_openTabs.isNotEmpty ? _openTabs.first : null);
    }

    if (_selectedTab != null) {
      _activeFilePath = _selectedTab!.filePath;
      _activeCode = _selectedTab!.isLoaded
          ? _selectedTab!.controller.text
          : (widget.initialCode ?? '');
    } else {
      _activeFilePath = widget.contextDescription;
      _activeCode = widget.initialCode;
    }

    if (widget.workspaceFolder != null && widget.workspaceFolder!.isNotEmpty) {
      _activeWorkspaceFolder = widget.workspaceFolder;
    } else if (sl.isRegistered<FsService>()) {
      final root = sl<FsService>().rootPath;
      final parts = root.split('/').where((s) => s.isNotEmpty).toList();
      _activeWorkspaceFolder = parts.isNotEmpty ? parts.last : 'workspace';
    }
  }

  void _switchTargetTab(EditorTab tab) {
    if (_selectedTab == tab) return;
    Haptics.onTabSwitch();
    setState(() {
      _selectedTab = tab;
      _activeFilePath = tab.filePath;
      _activeCode = tab.isLoaded ? tab.controller.text : '';
    });
  }

  @override
  void dispose() {
    _promptController.dispose();
    _apiKeyController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _checkKey() async {
    if (!sl.isRegistered<AiService>()) return;
    final ai = sl<AiService>();
    final key = await ai.getApiKey();
    if (mounted) {
      String? model;
      final provider =
          (key != null && key.isNotEmpty) ? detectAiProvider(key) : AiProvider.unknown;
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

      if (key != null &&
          widget.defaultPrompt != null &&
          widget.defaultPrompt!.isNotEmpty) {
        _sendPrompt(widget.defaultPrompt!);
      }
    }
  }

  bool _isProUser() {
    if (!sl.isRegistered<EntitlementService>()) return false;
    return sl<EntitlementService>().isRuntimeUnlocked('');
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String? _extractCodeBlock(String response) {
    final match =
        RegExp(r'```(?:\w+)?\s*\n([\s\S]*?)\n```', multiLine: true).firstMatch(response);
    if (match != null && match.group(1) != null) {
      return match.group(1)!.trim();
    }
    return null;
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
          _sendPrompt(widget.defaultPrompt!);
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

  Future<void> _sendPrompt(String promptText) async {
    final cleanPrompt = promptText.trim();
    if (cleanPrompt.isEmpty) return;
    Haptics.light();

    final isPro = _isProUser();
    final ai = sl<AiService>();

    if (!ai.canRequest(isPro)) {
      if (mounted) {
        final boughtPro = await showProPaywallSheet(context);
        if (boughtPro && mounted) {
          _sendPrompt(promptText);
        }
      }
      return;
    }

    // Immediately clear input and append user bubble so it pops up
    _promptController.clear();
    setState(() {
      _messages.add(AiChatMessage(role: 'user', content: cleanPrompt));
      _loading = true;
      _error = null;
    });
    _scrollToBottom();

    // Build background context for system prompt
    final currentFile = _activeFilePath ?? widget.contextDescription;
    final currentCode = _activeCode ?? widget.initialCode;
    final currentFolder = _activeWorkspaceFolder ?? widget.workspaceFolder;
    final lang = KriyaAiContext.inferLanguage(currentFile);
    final openFileNames = _openTabs.map((t) => t.name).toList();

    final systemPrompt = KriyaAiContext.buildSystemPrompt(
      filePath: currentFile,
      languageId: lang != 'text' ? lang : null,
      workspaceFolder: currentFolder,
      diagnosticsSummary: widget.diagnosticsSummary,
      fileContent: currentCode,
      openFiles: openFileNames,
    );

    // Prepare multi-turn messages
    final apiMessages = <Map<String, String>>[];
    for (final m in _messages) {
      apiMessages.add({
        'role': m.role,
        'content': m.content,
      });
    }

    try {
      final res = await ai.chat(
        messages: apiMessages,
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
          _messages.add(AiChatMessage(role: 'assistant', content: res));
          _loading = false;
          _verifiedModel = activeModel;
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _messages.add(
            AiChatMessage(
              role: 'assistant',
              content: 'Error: ${e.toString()}',
              isError: true,
            ),
          );
          _loading = false;
        });
        _scrollToBottom();
      }
    }
  }

  void _applyCode(AiChatMessage message, String code) {
    Haptics.medium();
    if (_selectedTab != null && _selectedTab!.isLoaded) {
      _selectedTab!.controller.text = code;
      _selectedTab!.checkDirty();
    }
    if (widget.onApplyCode != null) {
      widget.onApplyCode!(code);
    } else if (widget.onInsert != null) {
      widget.onInsert!(code);
    }
    setState(() {
      message.codeApplied = true;
    });
    final targetName = _selectedTab?.name ?? (_activeFilePath?.split('/').last ?? 'editor');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Applied code to $targetName in real-time!'),
        backgroundColor: const Color(0xFF00E676),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
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
          style: TextStyle(
            color: Color(0xFF00E676),
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
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
        maxHeight: media.size.height * 0.90,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF0B0F17),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(top: 10, bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Header: Sparkle + Title + Quota + Close (No file name banner!)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF00E676).withValues(alpha: 0.15),
                    ),
                    child: const Icon(
                      Icons.auto_awesome_rounded,
                      color: Color(0xFF00E676),
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Kriya AI Assistant',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        if (_configuredKey != null &&
                            _detectedProvider != AiProvider.unknown)
                          Text(
                            _verifiedModel != null
                                ? '${_detectedProvider.displayName} • $_verifiedModel'
                                : _detectedProvider.displayName,
                            style: const TextStyle(
                              color: Color(0xFF00E676),
                              fontSize: 10.5,
                              fontWeight: FontWeight.w500,
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
                    icon: const Icon(Icons.close_rounded, size: 20, color: Colors.white70),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            if (_configuredKey != null) _buildTargetFileBar(),
            const Divider(height: 1, color: Color(0xFF1E293B)),
            // Body: Key setup or ChatGPT-style Chat Stream
            Expanded(
              child: _configuredKey == null
                  ? SingleChildScrollView(child: _buildKeySetup(theme))
                  : _buildChatStream(),
            ),
            // Bottom Input Bar (Pinned at bottom, ChatGPT style)
            if (_configuredKey != null) _buildBottomInputBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildTargetFileBar() {
    if (_openTabs.isEmpty && (_activeFilePath == null || _activeFilePath!.isEmpty)) {
      return const SizedBox.shrink();
    }

    final folder = _activeWorkspaceFolder ?? 'Project';

    if (_openTabs.length > 1) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        color: const Color(0xFF0C1322),
        child: Row(
          children: [
            const Icon(Icons.folder_open_rounded, size: 14, color: Color(0xFF38BDF8)),
            const SizedBox(width: 5),
            Text(
              folder,
              style: const TextStyle(
                color: Color(0xFF38BDF8),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              '|',
              style: TextStyle(color: Colors.white24, fontSize: 11),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _openTabs.map((tab) {
                    final isSelected = tab == _selectedTab || tab.filePath == _activeFilePath;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: InkWell(
                        onTap: () => _switchTargetTab(tab),
                        borderRadius: BorderRadius.circular(12),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? const Color(0xFF2563EB).withValues(alpha: 0.25)
                                : const Color(0xFF161F2E),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected
                                  ? const Color(0xFF3B82F6)
                                  : const Color(0xFF1E293B),
                              width: isSelected ? 1.2 : 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.description_outlined,
                                size: 12,
                                color: isSelected ? const Color(0xFF60A5FA) : Colors.white60,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                tab.name,
                                style: TextStyle(
                                  color: isSelected ? const Color(0xFF60A5FA) : Colors.white70,
                                  fontSize: 11,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                              if (isSelected) ...[
                                const SizedBox(width: 4),
                                const Icon(Icons.check_circle_rounded, size: 11, color: Color(0xFF60A5FA)),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final fileName = _activeFilePath?.split('/').last ?? 'Current File';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      color: const Color(0xFF0C1322),
      child: Row(
        children: [
          const Icon(Icons.folder_open_rounded, size: 13, color: Color(0xFF38BDF8)),
          const SizedBox(width: 5),
          Text(
            folder,
            style: const TextStyle(
              color: Color(0xFF38BDF8),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 6),
          const Text('/', style: TextStyle(color: Colors.white24, fontSize: 11)),
          const SizedBox(width: 6),
          const Icon(Icons.description_outlined, size: 13, color: Color(0xFF00E676)),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              fileName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF00E676).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text(
              'Active Context',
              style: TextStyle(
                color: Color(0xFF00E676),
                fontSize: 9.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKeySetup(ThemeData theme) {
    final previewProvider = detectAiProvider(_apiKeyController.text);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF111827),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF1F2937)),
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
          const SizedBox(height: 14),
          TextField(
            controller: _apiKeyController,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontFamily: 'monospace',
            ),
            decoration: InputDecoration(
              hintText: 'Paste key (AIzaSy..., gsk_..., sk-...)',
              hintStyle: const TextStyle(color: Colors.white30, fontSize: 12),
              filled: true,
              fillColor: const Color(0xFF111827),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFF1F2937)),
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
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 12),
            ),
          ],
          const SizedBox(height: 16),
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
                onPressed:
                    (_apiKeyController.text.trim().isEmpty || _validatingKey)
                        ? null
                        : _saveApiKey,
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

  Widget _buildChatStream() {
    if (_messages.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF00E676).withValues(alpha: 0.12),
                  border: Border.all(
                    color: const Color(0xFF00E676).withValues(alpha: 0.3),
                    width: 1.5,
                  ),
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: Color(0xFF00E676),
                  size: 28,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'How can I help you today?',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Ask questions, solve syntax errors, or explain code.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  _buildQuickChip(
                    'Explain Code',
                    _selectedTab != null
                        ? 'Explain what ${_selectedTab!.name} does clearly and concisely.'
                        : 'Explain what this code does clearly and concisely.',
                  ),
                  _buildQuickChip(
                    'Find & Fix Bugs',
                    _selectedTab != null
                        ? 'Analyze ${_selectedTab!.name} for bugs, edge cases, and syntax errors, and show the corrected code.'
                        : 'Analyze this code for bugs or edge cases and show the corrected code.',
                  ),
                  _buildQuickChip(
                    'Add Comments',
                    _selectedTab != null
                        ? 'Add clear, helpful comments to ${_selectedTab!.name} without changing its logic.'
                        : 'Add clear, helpful comments to this code without changing its logic.',
                  ),
                  _buildQuickChip(
                    'Optimize',
                    _selectedTab != null
                        ? 'Optimize ${_selectedTab!.name} for better performance and readability.'
                        : 'Optimize this code for better performance and readability.',
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      itemCount: _messages.length + (_loading ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _messages.length && _loading) {
          return _buildThinkingBubble();
        }
        final msg = _messages[index];
        return msg.role == 'user'
            ? _buildUserMessage(msg)
            : _buildAssistantMessage(msg);
      },
    );
  }

  Widget _buildQuickChip(String label, String prompt) {
    return ActionChip(
      backgroundColor: const Color(0xFF161F2E),
      side: const BorderSide(color: Color(0xFF1E293B)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      label: Text(
        label,
        style: const TextStyle(color: Colors.white70, fontSize: 12),
      ),
      onPressed: () => _sendPrompt(prompt),
    );
  }

  Widget _buildUserMessage(AiChatMessage message) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14, left: 48),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1D4ED8), Color(0xFF2563EB)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(18),
                  topRight: Radius.circular(18),
                  bottomLeft: Radius.circular(18),
                  bottomRight: Radius.circular(4),
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF2563EB).withValues(alpha: 0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: SelectableText(
                message.content,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  height: 1.35,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAssistantMessage(AiChatMessage message) {
    final codeBlock = _extractCodeBlock(message.content);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16, right: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            margin: const EdgeInsets.only(top: 2, right: 10),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF00E676).withValues(alpha: 0.15),
              border: Border.all(
                color: const Color(0xFF00E676).withValues(alpha: 0.35),
                width: 1,
              ),
            ),
            child: const Icon(
              Icons.auto_awesome,
              color: Color(0xFF00E676),
              size: 14,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: message.isError
                        ? const Color(0xFF321313)
                        : const Color(0xFF131A26),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(4),
                      topRight: Radius.circular(18),
                      bottomLeft: Radius.circular(18),
                      bottomRight: Radius.circular(18),
                    ),
                    border: Border.all(
                      color: message.isError
                          ? Colors.redAccent.withValues(alpha: 0.4)
                          : const Color(0xFF1E293B),
                    ),
                  ),
                  child: SelectableText(
                    message.content,
                    style: TextStyle(
                      color: message.isError ? Colors.redAccent : Colors.white,
                      fontSize: 13.5,
                      height: 1.4,
                    ),
                  ),
                ),
                // Action Buttons below Assistant Message
                Padding(
                  padding: const EdgeInsets.only(top: 6, left: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      InkWell(
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: message.content));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Copied response to clipboard'),
                              duration: Duration(seconds: 1),
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(6),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.copy_rounded, size: 14, color: Colors.white54),
                              SizedBox(width: 4),
                              Text('Copy', style: TextStyle(color: Colors.white54, fontSize: 11)),
                            ],
                          ),
                        ),
                      ),
                      if (codeBlock != null && (widget.onApplyCode != null || widget.onInsert != null)) ...[
                        const SizedBox(width: 10),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: message.codeApplied
                                ? const Color(0xFF1B5E20)
                                : const Color(0xFF00E676),
                            foregroundColor: message.codeApplied ? Colors.white : Colors.black,
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                          icon: Icon(
                            message.codeApplied
                                ? Icons.check_circle_rounded
                                : Icons.bolt_rounded,
                            size: 14,
                          ),
                          label: Text(
                            message.codeApplied
                                ? 'Applied to Editor'
                                : 'Apply to Editor (Real-time)',
                          ),
                          onPressed: () => _applyCode(message, codeBlock),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThinkingBubble() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14, right: 48),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 28,
            height: 28,
            margin: const EdgeInsets.only(right: 10),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF00E676).withValues(alpha: 0.15),
            ),
            child: const Icon(
              Icons.auto_awesome,
              color: Color(0xFF00E676),
              size: 14,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF131A26),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF1E293B)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00E676)),
                  ),
                ),
                SizedBox(width: 8),
                Text(
                  'Kriya AI is thinking…',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomInputBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF0B0F17),
        border: Border(top: BorderSide(color: Color(0xFF1E293B))),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _promptController,
              minLines: 1,
              maxLines: 4,
              style: const TextStyle(color: Colors.white, fontSize: 13.5),
              decoration: InputDecoration(
                hintText: 'Message Kriya AI...',
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                filled: true,
                fillColor: const Color(0xFF161F2E),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: const BorderSide(color: Color(0xFF1E293B)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: const BorderSide(color: Color(0xFF1E293B)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: const BorderSide(color: Color(0xFF00E676)),
                ),
              ),
              onSubmitted: (text) => _sendPrompt(text),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFF00E676),
              foregroundColor: Colors.black,
              shape: const CircleBorder(),
              padding: const EdgeInsets.all(10),
            ),
            icon: const Icon(Icons.arrow_upward_rounded, size: 20),
            onPressed: _loading ? null : () => _sendPrompt(_promptController.text),
          ),
        ],
      ),
    );
  }
}
