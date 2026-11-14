import 'package:flutter/material.dart';

import '../lsp/diagnostics.dart';

/// The inline diagnostics for the active document.
///
/// One row per problem, in document order, with the line number first because
/// that is what the user needs in order to act on it. A long list is capped
/// with a count rather than a scroll view: this sits directly above the keyboard
/// on a phone, and a tall panel would take the code off screen.
class DiagnosticsBar extends StatelessWidget {
  final List<Diagnostic> diagnostics;
  final ValueChanged<Diagnostic> onSelect;

  const DiagnosticsBar({
    super.key,
    required this.diagnostics,
    required this.onSelect,
  });

  static const int _maxRows = 3;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final shown = diagnostics.take(_maxRows);
    final hidden = diagnostics.length - shown.length;

    return Container(
      width: double.infinity,
      color: cs.errorContainer,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final diagnostic in shown)
            Semantics(
              button: true,
              label: 'Line ${diagnostic.line + 1}: ${diagnostic.message}',
              child: InkWell(
                onTap: () => onSelect(diagnostic),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, size: 14, color: cs.onErrorContainer),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Line ${diagnostic.line + 1}: ${diagnostic.message}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: cs.onErrorContainer),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (hidden > 0)
            Text(
              '+$hidden more',
              style: TextStyle(fontSize: 11, color: cs.onErrorContainer.withValues(alpha: 0.75)),
            ),
        ],
      ),
    );
  }
}
