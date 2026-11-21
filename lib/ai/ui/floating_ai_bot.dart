import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/haptics.dart';
import '../../editor/tab_manager.dart';
import '../../lsp/diagnostics.dart';
import 'ai_assist_sheet.dart';

class FloatingAiBot extends StatefulWidget {
  final EditorTab? tab;
  final List<Diagnostic> diagnostics;
  final String? customErrorMessage;
  final String workspaceRoot;
  final void Function(String newCode)? onApplyCode;
  final VoidCallback onDismiss;

  const FloatingAiBot({
    super.key,
    required this.tab,
    required this.diagnostics,
    this.customErrorMessage,
    required this.workspaceRoot,
    this.onApplyCode,
    required this.onDismiss,
  });

  @override
  State<FloatingAiBot> createState() => _FloatingAiBotState();
}

class _FloatingAiBotState extends State<FloatingAiBot>
    with TickerProviderStateMixin {
  late final AnimationController _slideController;
  late final Animation<Offset> _slideAnimation;

  late final AnimationController _waveController;
  late final Animation<double> _waveAnimation;

  bool _dismissed = false;
  String? _lastDismissedError;

  @override
  void initState() {
    super.initState();

    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(1.2, 0.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutBack,
    ));

    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    _waveAnimation = Tween<double>(begin: -0.25, end: 0.25).animate(
      CurvedAnimation(
        parent: _waveController,
        curve: Curves.easeInOutSine,
      ),
    );

    _updateErrorState();
  }

  @override
  void didUpdateWidget(covariant FloatingAiBot oldWidget) {
    super.didUpdateWidget(oldWidget);
    final currentError = _getCurrentErrorMessage();
    if (currentError != null && currentError != _lastDismissedError) {
      _dismissed = false;
    }
    _updateErrorState();
  }

  String? _getCurrentErrorMessage() {
    if (widget.customErrorMessage != null &&
        widget.customErrorMessage!.isNotEmpty) {
      return widget.customErrorMessage;
    }
    if (widget.diagnostics.isNotEmpty) {
      final d = widget.diagnostics.first;
      return 'L${d.line}: ${d.message}';
    }
    return null;
  }

  void _updateErrorState() {
    final hasError = _getCurrentErrorMessage() != null && !_dismissed;
    if (hasError) {
      if (!_slideController.isCompleted && !_slideController.isAnimating) {
        _slideController.forward();
      }
      if (!_waveController.isAnimating) {
        _waveController.repeat(reverse: true);
      }
    } else {
      if (_slideController.value > 0 && !_slideController.isAnimating) {
        _slideController.reverse();
      }
      if (_waveController.isAnimating) {
        _waveController.stop();
        _waveController.reset();
      }
    }
  }

  @override
  void dispose() {
    _slideController.dispose();
    _waveController.dispose();
    super.dispose();
  }

  void _openAiSheet() {
    Haptics.light();
    final tab = widget.tab;
    final folderName = widget.workspaceRoot.isNotEmpty
        ? p.basename(widget.workspaceRoot)
        : null;

    String? relPath;
    if (tab != null && widget.workspaceRoot.isNotEmpty) {
      relPath = p.isWithin(widget.workspaceRoot, tab.filePath)
          ? p.relative(tab.filePath, from: widget.workspaceRoot)
          : tab.name;
    } else if (tab != null) {
      relPath = tab.name;
    }

    final diagSummary = widget.diagnostics.map((d) {
      return 'Line ${d.line}, Col ${d.column}: ${d.message}';
    }).toList();

    String? prompt;
    if (widget.customErrorMessage != null) {
      prompt =
          'Fix syntax/runtime error: "${widget.customErrorMessage}". Provide the working code to apply in realtime.';
    } else if (widget.diagnostics.isNotEmpty) {
      final d = widget.diagnostics.first;
      prompt =
          'Fix syntax error on Line ${d.line}: "${d.message}". Provide the working code to apply in realtime.';
    }

    AiAssistSheet.show(
      context,
      initialCode: tab?.controller.text,
      contextDescription: relPath,
      workspaceFolder: folderName,
      diagnosticsSummary: diagSummary,
      defaultPrompt: prompt,
      onApplyCode: widget.onApplyCode,
      onInsert: (code) {
        if (tab != null) {
          tab.controller.text = code;
          tab.checkDirty();
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final errorMessage = _getCurrentErrorMessage();
    if (errorMessage == null || _dismissed) {
      // User requirement 2: "I dont want a floating AI logo it should only pop up smartly when user does syntax error"
      return const SizedBox.shrink();
    }

    final media = MediaQuery.of(context);
    final size = media.size;
    final safeBottom = media.padding.bottom + 115.0;

    return Positioned(
      right: 12,
      bottom: safeBottom,
      child: SlideTransition(
        position: _slideAnimation,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _openAiSheet,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              constraints: BoxConstraints(maxWidth: size.width - 24),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF161F2E), Color(0xFF0F172A)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color(0xFFFFB300),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFFB300).withValues(alpha: 0.3),
                    blurRadius: 16,
                    spreadRadius: 2,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Cute Mini Bot with waving robotic hand
                  SizedBox(
                    width: 44,
                    height: 44,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Bot head
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const LinearGradient(
                              colors: [Color(0xFF372005), Color(0xFF1E1303)],
                            ),
                            border: Border.all(
                              color: const Color(0xFFFFB300),
                              width: 1.8,
                            ),
                          ),
                          child: const Icon(
                            Icons.smart_toy_rounded,
                            size: 20,
                            color: Color(0xFFFFB300),
                          ),
                        ),
                        // Animated waving robotic hand
                        Positioned(
                          top: 0,
                          right: 0,
                          child: AnimatedBuilder(
                            animation: _waveAnimation,
                            builder: (context, child) {
                              return Transform.rotate(
                                angle: _waveAnimation.value,
                                alignment: Alignment.bottomLeft,
                                child: Container(
                                  padding: const EdgeInsets.all(2),
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF2E1903),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.waving_hand_rounded,
                                    size: 15,
                                    color: Color(0xFFFFD54F),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  // "Click me to fix this" + error subtitle
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Click me to fix this',
                              style: TextStyle(
                                color: Color(0xFFFFB300),
                                fontSize: 12.5,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.2,
                              ),
                            ),
                            SizedBox(width: 4),
                            Icon(
                              Icons.arrow_forward_rounded,
                              size: 13,
                              color: Color(0xFFFFB300),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          errorMessage,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 10.5,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Dismiss button
                  InkWell(
                    onTap: () {
                      Haptics.light();
                      setState(() {
                        _dismissed = true;
                        _lastDismissedError = errorMessage;
                      });
                      widget.onDismiss();
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(
                        Icons.close_rounded,
                        size: 16,
                        color: Colors.white54,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
