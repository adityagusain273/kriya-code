import 'package:flutter/widgets.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:highlight/highlight.dart';

class BCodeController extends CodeController {
  BCodeController({
    super.text,
    super.language,
    super.params,
  });

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    bool? withComposing,
  }) {
    _splitStringNodes();
    _colorizeBrackets();
    return super.buildTextSpan(
      context: context,
      style: style,
      withComposing: withComposing,
    );
  }

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
          final matches = RegExp(r'[\[\]\(\)\{\}]').allMatches(val);
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
