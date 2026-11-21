import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/haptics.dart';
import '../../editor/tab_manager.dart';
import '../../lsp/diagnostics.dart';
import 'ai_assist_sheet.dart';

class FloatingAiBot extends StatefulWidget {
  final EditorTab? tab;
  final List<Diagnostic> diagnostics;
  final String workspaceRoot;
  final void Function(String newCode)? onApplyCode;
  final VoidCallback onDismiss;

  const FloatingAiBot({
    super.key,
    required this.tab,
    required this.diagnostics,
    required this.workspaceRoot,
    this.onApplyCode,
    required this.onDismiss,
  });

  @override
  State<FloatingAiBot> createState() => _FloatingAiBotState();
}

class _FloatingAiBotState extends State<FloatingAiBot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _waveController;
  late final Animation<double> _waveAnimation;

  Offset? _position;
  bool _isDragging = false;
  bool _dismissHovered = false;
  bool _bubbleDismissedForCurrentError = false;
  String? _lastDismissedError;

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    _waveAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: -0.22)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 25,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: -0.22, end: 0.22)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.22, end: 0.0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 25,
      ),
    ]).animate(_waveController);

    _updateWaveState();
  }

  @override
  void didUpdateWidget(covariant FloatingAiBot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.diagnostics.isNotEmpty) {
      final firstMsg = widget.diagnostics.first.message;
      if (firstMsg != _lastDismissedError) {
        _bubbleDismissedForCurrentError = false;
      }
    }
    _updateWaveState();
  }

  void _updateWaveState() {
    if (widget.diagnostics.isNotEmpty) {
      if (!_waveController.isAnimating) {
        _waveController.repeat();
      }
    } else {
      if (_waveController.isAnimating) {
        _waveController.stop();
        _waveController.reset();
      }
    }
  }

  @override
  void dispose() {
    _waveController.dispose();
    super.dispose();
  }

  void _openAiSheet({String? customPrompt}) {
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

    String? prompt = customPrompt;
    if (prompt == null && widget.diagnostics.isNotEmpty) {
      final d = widget.diagnostics.first;
      prompt =
          'Fix syntax error on Line ${d.line}: "${d.message}" in ${tab?.name ?? "this file"}. Provide the working code to apply in realtime.';
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
    final media = MediaQuery.of(context);
    final size = media.size;
    final safeTop = media.padding.top + 50.0;
    final safeBottom = media.padding.bottom + 115.0;

    _position ??= Offset(
      size.width - 66.0,
      size.height - safeBottom - 60.0,
    );

    final currentPos = _isDragging
        ? _position!
        : Offset(
            _position!.dx.clamp(8.0, size.width - 56.0),
            _position!.dy.clamp(safeTop, size.height - safeBottom - 56.0),
          );

    final hasErrors = widget.diagnostics.isNotEmpty;
    final firstError = hasErrors ? widget.diagnostics.first : null;
    final showBubble = hasErrors && !_bubbleDismissedForCurrentError && !_isDragging;

    final dismissRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height - safeBottom + 15),
      width: 240,
      height: 80,
    );

    return Positioned.fill(
      child: Stack(
        children: [
          if (_isDragging)
            Positioned(
              key: const ValueKey('dismiss_target'),
              left: dismissRect.left,
              top: dismissRect.top,
              width: dismissRect.width,
              height: dismissRect.height,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                decoration: BoxDecoration(
                  color: _dismissHovered
                      ? const Color(0xFFD32F2F)
                      : const Color(0xFF1E293B).withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: _dismissHovered
                        ? Colors.redAccent
                        : Colors.white24,
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: (_dismissHovered ? Colors.red : Colors.black)
                          .withValues(alpha: 0.4),
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: _dismissHovered ? Colors.white : Colors.white70,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Drag here to hide',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _dismissHovered ? Colors.white : Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          if (showBubble && firstError != null)
            Positioned(
              key: const ValueKey('error_bubble'),
              left: (currentPos.dx - 220).clamp(12.0, size.width - 240),
              top: (currentPos.dy - 6).clamp(safeTop, size.height - safeBottom - 50),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _openAiSheet(),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 215,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF111827),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFFFFB300),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFFB300).withValues(alpha: 0.25),
                          blurRadius: 12,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            const Text('👋', style: TextStyle(fontSize: 13)),
                            const SizedBox(width: 4),
                            const Expanded(
                              child: Text(
                                'Syntax Issue • Tap to fix',
                                style: TextStyle(
                                  color: Color(0xFFFFB300),
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            InkWell(
                              onTap: () {
                                setState(() {
                                  _bubbleDismissedForCurrentError = true;
                                  _lastDismissedError = firstError.message;
                                });
                              },
                              borderRadius: BorderRadius.circular(8),
                              child: const Padding(
                                padding: EdgeInsets.all(2.0),
                                child: Icon(Icons.close, size: 13, color: Colors.white54),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'L${firstError.line}: ${firstError.message}',
                          maxLines: 2,
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
                ),
              ),
            ),

          Positioned(
            key: const ValueKey('bot_button'),
            left: currentPos.dx,
            top: currentPos.dy,
            child: GestureDetector(
              onPanStart: (_) {
                setState(() {
                  _isDragging = true;
                });
              },
              onPanUpdate: (details) {
                final newPos = _position! + details.delta;
                final isHovering = (newPos.dy > size.height - safeBottom - 50) &&
                    ((newPos.dx + 25) - size.width / 2).abs() < 130;
                setState(() {
                  _position = newPos;
                  _dismissHovered = isHovering;
                });
              },
              onPanEnd: (_) {
                if (_dismissHovered) {
                  Haptics.medium();
                  widget.onDismiss();
                } else {
                  setState(() {
                    _isDragging = false;
                    _dismissHovered = false;
                    _position = Offset(
                      _position!.dx.clamp(8.0, size.width - 56.0),
                      _position!.dy.clamp(safeTop, size.height - safeBottom - 56.0),
                    );
                  });
                }
              },
              onTap: () => _openAiSheet(),
              child: AnimatedBuilder(
                animation: _waveAnimation,
                builder: (context, child) {
                  final angle = hasErrors ? _waveAnimation.value : 0.0;
                  return Transform.rotate(
                    angle: angle,
                    child: Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: hasErrors
                              ? const [Color(0xFF372005), Color(0xFF1E1303)]
                              : const [Color(0xFF0F231B), Color(0xFF0A1512)],
                        ),
                        border: Border.all(
                          color: hasErrors
                              ? const Color(0xFFFFB300)
                              : const Color(0xFF00E676),
                          width: 2.0,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: (hasErrors
                                    ? const Color(0xFFFFB300)
                                    : const Color(0xFF00E676))
                                .withValues(alpha: 0.4),
                            blurRadius: hasErrors ? 14 : 8,
                            spreadRadius: hasErrors ? 2 : 0,
                          ),
                        ],
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Icon(
                            hasErrors
                                ? Icons.smart_toy_rounded
                                : Icons.auto_awesome_rounded,
                            size: 24,
                            color: hasErrors
                                ? const Color(0xFFFFB300)
                                : const Color(0xFF00E676),
                          ),
                          if (hasErrors)
                            Positioned(
                              top: 2,
                              right: 2,
                              child: Container(
                                width: 11,
                                height: 11,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFFF3D00),
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
