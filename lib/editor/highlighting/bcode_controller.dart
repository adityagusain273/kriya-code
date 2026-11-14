import 'package:flutter/widgets.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:highlight/highlight.dart';

import '../../lsp/diagnostics.dart';
import 'diagnostic_highlight_builder.dart';

class BCodeController extends CodeController {
  BCodeController({
    super.text,
    super.language,
    super.params,
  });

  List<Diagnostic> _diagnostics = const [];

  List<Diagnostic> get diagnostics => _diagnostics;

  set diagnostics(List<Diagnostic> val) {
    if (_diagnostics != val) {
      _diagnostics = val;
      notifyListeners();
    }
  }

  /// Pairs whose closing half the editor inserts automatically, mapped to the
  /// character the user has to type to move past it.
  static const _closers = <String, String>{
    ')': '(',
    ']': '[',
    '}': '{',
    '"': '"',
    "'": "'",
    '`': '`',
  };

  /// Steps over an auto-inserted closing character rather than duplicating it.
  ///
  /// Typing `(` already produces `()` with the caret between them. Typing the `)`
  /// next is the natural keystroke, and without this it produced `())` — unbalanced
  /// code that then failed to run, which is a poor first experience on a phone.
  ///
  /// Done here rather than through the editor's [CodeModifier] hook because that
  /// table is keyed by character: registering a handler for `"` replaces the
  /// package's own quote insertion, and adding one for `)` ran into assumptions in
  /// the package's read-only range check that a shrinking edit violates.
  @override
  set value(TextEditingValue newValue) {
    final adjusted = _stepOverClosingCharacter(newValue);
    super.value = adjusted ?? newValue;
  }

  TextEditingValue? _stepOverClosingCharacter(TextEditingValue incoming) {
    final current = super.value;
    if (incoming.text.length != current.text.length + 1) return null;
    final sel = current.selection;
    if (!sel.isCollapsed || sel.start < 0) return null;
    if (sel.start >= current.text.length) return null;

    // The character that was just typed sits immediately before the caret in the
    // incoming text; the caret itself has already moved past it.
    final typed = incoming.text[sel.start];
    final opener = _closers[typed];
    if (opener == null) return null;

    // There must be an identical closer already sitting at the caret, and it must
    // belong to a pair that is still open. Otherwise this keystroke is genuine,
    // such as the bracket in `print(1) + 2)`.
    if (current.text[sel.start] != typed) return null;
    if (!_isPairPending(current.text, sel.start, opener, typed)) return null;

    return TextEditingValue(
      text: current.text,
      selection: TextSelection.collapsed(offset: sel.start + 1),
    );
  }

  /// Whether a pair opened by [opener] is still open before [caret].
  static bool _isPairPending(
    String text,
    int caret,
    String opener,
    String closer,
  ) {
    var open = 0;
    var close = 0;
    for (var i = 0; i < caret; i++) {
      final ch = text[i];
      if (ch == opener) open++;
      // Quotes are their own opener and closer, so they must not cancel themselves
      // out or an empty string would look unclosed.
      if (ch == closer && closer != opener) close++;
    }
    return open > close;
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    bool? withComposing,
  }) {
    // Both transforms rebuild the entire node tree. `buildTextSpan` runs on
    // every frame that repaints the field, including plain selection changes,
    // and re-decorating an already-decorated tree wrapped nodes repeatedly.
    final highlighted = code.visibleHighlighted;
    if (highlighted?.nodes != null &&
        !identical(highlighted!.nodes, _decoratedNodes)) {
      _splitStringNodes();
      _colorizeBrackets();
      _decoratedNodes = highlighted.nodes;
    }
    final span = super.buildTextSpan(
      context: context,
      style: style,
      withComposing: withComposing,
    );

    if (_diagnostics.isEmpty) {
      return span;
    }

    return DiagnosticHighlightedBuilder(
      diagnostics: _diagnostics,
      textLength: text.length,
      rootStyle: style,
      textSpan: span,
    ).build();
  }

  List<Node>? _decoratedNodes;

  static final _bracketPattern = RegExp(r'[\[\]\(\)\{\}]');

  void _colorizeBrackets() {
    final highlighted = code.visibleHighlighted;
    if (highlighted == null || highlighted.nodes == null) return;
    
    int depth = 0;
    
    List<Node> process(List<Node> input, String? parentClass) {
      final result = <Node>[];
      for (final node in input) {
        final currentClass = node.className ?? parentClass;
        
        if (currentClass == 'string' || currentClass == 'comment') {
          result.add(node);
          continue;
        }
        
        if (node.children != null && node.children!.isNotEmpty) {
          result.add(Node(
            className: node.className,
            children: process(node.children!, currentClass),
            noPrefix: node.noPrefix,
          ));
        } else if (node.value != null) {
          final val = node.value!;
          int lastMatchEnd = 0;
          final matches = _bracketPattern.allMatches(val);
          for (final match in matches) {
            if (match.start > lastMatchEnd) {
              result.add(Node(className: node.className, value: val.substring(lastMatchEnd, match.start)));
            }
            final bracket = match.group(0)!;
            final isOpening = bracket == '(' || bracket == '[' || bracket == '{';
            final isClosing = bracket == ')' || bracket == ']' || bracket == '}';
            
            if (isOpening) {
              depth++;
              final classDepth = ((depth - 1) % 8) + 1;
              result.add(Node(className: 'bracket-$classDepth', value: bracket));
            } else if (isClosing) {
              final classDepth = depth > 0 ? ((depth - 1) % 8) + 1 : 1;
              result.add(Node(className: 'bracket-$classDepth', value: bracket));
              depth--;
              if (depth < 0) depth = 0;
            }
            lastMatchEnd = match.end;
          }
          if (lastMatchEnd < val.length) {
            result.add(Node(className: node.className, value: val.substring(lastMatchEnd)));
          }
        } else {
          result.add(node);
        }
      }
      return result;
    }
    
    highlighted.nodes = process(highlighted.nodes!, null);
  }

  void _splitStringNodes() {
    final highlighted = code.visibleHighlighted;
    if (highlighted == null || highlighted.nodes == null) return;

    final original = highlighted.nodes!;
    final newNodes = <Node>[];
    for (final node in original) {
      newNodes.addAll(_processNode(node));
    }
    highlighted.nodes = newNodes;
  }

  List<Node> _processNode(Node node) {
    if (node.className == 'string') {
      if (node.children != null && node.children!.isNotEmpty) {
        return _splitStringChildren(node);
      }
      return [node];
    }

    if (node.children != null && node.children!.isNotEmpty) {
      final newChildren = <Node>[];
      for (final child in node.children!) {
        newChildren.addAll(_processNode(child));
      }
      return [
        Node(className: node.className, children: newChildren, noPrefix: node.noPrefix)
      ];
    }

    return [node];
  }

  static const _prefixes = {'f', 'r', 'u', 'b'};

  static int _countLeadingQuotes(String s, int start) {
    if (start >= s.length) return 0;
    final ch = s[start];
    if (ch != '"' && ch != "'") return 0;
    int count = 0;
    for (int i = start; i < s.length && i < start + 3; i++) {
      if (s[i] == ch) {
        count++;
      } else {
        break;
      }
    }
    return count;
  }

  static int _countTrailingQuotes(String s, int end) {
    if (end <= 0) return 0;
    final ch = s[end - 1];
    if (ch != '"' && ch != "'") return 0;
    int count = 0;
    for (int i = end - 1; i >= 0 && i > end - 4; i--) {
      if (s[i] == ch) {
        count++;
      } else {
        break;
      }
    }
    return count;
  }

  static int _skipPrefix(String s) {
    int i = 0;
    while (i < s.length && _prefixes.contains(s[i])) {
      i++;
    }
    return i;
  }

  List<Node> _splitStringValue(Node node) {
    final value = node.value!;
    final result = <Node>[];

    final prefixEnd = _skipPrefix(value);
    final openCount = _countLeadingQuotes(value, prefixEnd);

    if (openCount > 0) {
      final openQuote = value.substring(0, prefixEnd + openCount);
      result.add(Node(className: 'string', value: openQuote));

      final afterOpen = prefixEnd + openCount;
      final closeCount = _countTrailingQuotes(value, value.length);

      if (closeCount > 0 && openCount == closeCount &&
          afterOpen <= value.length - closeCount &&
          value.substring(value.length - closeCount) ==
              value.substring(prefixEnd, prefixEnd + openCount)) {
        final content = value.substring(afterOpen, value.length - closeCount);
        if (content.isNotEmpty) {
          result.add(Node(className: 'string', value: content));
        }
        result.add(
            Node(className: 'string', value: value.substring(value.length - closeCount)));
      } else {
        final content = value.substring(afterOpen);
        if (content.isNotEmpty) {
          result.add(Node(className: 'string', value: content));
        }
      }
    } else {
      final closeCount = _countTrailingQuotes(value, value.length);
      if (closeCount > 0 && closeCount <= value.length) {
        final content = value.substring(0, value.length - closeCount);
        if (content.isNotEmpty) {
          result.add(Node(className: 'string', value: content));
        }
        result.add(
            Node(className: 'string', value: value.substring(value.length - closeCount)));
      } else {
        result.add(node);
      }
    }

    return result;
  }

  List<Node> _splitStringChildren(Node node) {
    final children = node.children!;
    if (children.isEmpty) return [node];

    if (children.length == 1 && children.first.value != null) {
      return _splitStringValue(
        Node(className: 'string', value: children.first.value),
      );
    }

    final result = <Node>[];

    final first = children.first;
    if (first.value != null) {
      final prefixEnd = _skipPrefix(first.value!);
      final openCount = _countLeadingQuotes(first.value!, prefixEnd);
      if (openCount > 0) {
        final openQuote = first.value!.substring(0, prefixEnd + openCount);
        result.add(Node(className: 'string', value: openQuote));
        final rest = first.value!.substring(prefixEnd + openCount);
        if (rest.isNotEmpty) {
          result.add(Node(className: 'string', value: rest));
        }
      } else {
        result.add(first);
      }
    } else {
      result.add(first);
    }

    for (int i = 1; i < children.length - 1; i++) {
      result.add(children[i]);
    }

    if (children.length > 1) {
      final last = children.last;
      if (last.value != null) {
        final closeCount = _countTrailingQuotes(last.value!, last.value!.length);
        if (closeCount > 0) {
          final content =
              last.value!.substring(0, last.value!.length - closeCount);
          if (content.isNotEmpty) {
            result.add(Node(className: 'string', value: content));
          }
          result.add(Node(
              className: 'string',
              value: last.value!.substring(last.value!.length - closeCount)));
        } else {
          result.add(last);
        }
      } else {
        result.add(last);
      }
    }

    return result;
  }
}
