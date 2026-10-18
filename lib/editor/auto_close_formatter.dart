import 'package:flutter/services.dart';

class AutoCloseFormatter extends TextInputFormatter {
  static const _pairs = {
    '(': ')',
    '[': ']',
    '{': '}',
    '"': '"',
    "'": "'",
  };

  static const _closingChars = {')', ']', '}', '"', "'"};

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Handle deletion - if user deletes a pair, delete both
    if (newValue.text.length < oldValue.text.length) {
      return _handleDeletion(oldValue, newValue);
    }

    // Handle insertion
    if (newValue.text.length > oldValue.text.length) {
      return _handleInsertion(oldValue, newValue);
    }

    return newValue;
  }

  TextEditingValue _handleDeletion(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final oldText = oldValue.text;
    final oldSelection = oldValue.selection;

    // Check if we're deleting a pair (cursor between matching brackets)
    if (oldSelection.isCollapsed &&
        oldSelection.start > 0 &&
        oldSelection.start < oldText.length) {
      final charBefore = oldText[oldSelection.start - 1];
      final charAfter = oldSelection.start < oldText.length
          ? oldText[oldSelection.start]
          : '';

      // Check if they form a pair
      if (_pairs[charBefore] == charAfter) {
        // Delete both characters
        final updatedText = oldText.replaceRange(
          oldSelection.start - 1,
          oldSelection.start + 1,
          '',
        );
        return TextEditingValue(
          text: updatedText,
          selection: TextSelection.collapsed(offset: oldSelection.start - 1),
        );
      }
    }

    return newValue;
  }

  TextEditingValue _handleInsertion(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final oldText = oldValue.text;
    final newText = newValue.text;
    final oldSelection = oldValue.selection;
    final newSelection = newValue.selection;

    // Only handle single character insertion at cursor position
    if (!oldSelection.isCollapsed ||
        !newSelection.isCollapsed ||
        newSelection.start != oldSelection.start + 1) {
      return newValue;
    }

    final insertedChar = newText[oldSelection.start];

    // Handle opening bracket/quote
    if (_pairs.containsKey(insertedChar)) {
      final closingChar = _pairs[insertedChar]!;
      
      // Don't auto-close if:
      // 1. Next character is already the closing char
      // 2. We're inside a string (for quotes)
      // 3. Next char is a word character (for brackets)
      
      final nextChar = oldSelection.start < oldText.length
          ? oldText[oldSelection.start]
          : '';
      
      if (insertedChar == '"' || insertedChar == "'") {
        // For quotes, don't auto-close if next char is alphanumeric or another quote
        if (_isWordChar(nextChar) || _closingChars.contains(nextChar)) {
          return newValue;
        }
      } else {
        // For brackets, don't auto-close if next char is a word char
        if (_isWordChar(nextChar)) {
          return newValue;
        }
      }

      // Insert closing character after cursor
      final updatedText = newText.replaceRange(
        newSelection.start,
        newSelection.start,
        closingChar,
      );
      
      return TextEditingValue(
        text: updatedText,
        selection: TextSelection.collapsed(offset: newSelection.start),
      );
    }

    // Handle typing closing bracket/quote - skip over if matching
    if (_closingChars.contains(insertedChar)) {
      final nextChar = oldSelection.start < oldText.length
          ? oldText[oldSelection.start]
          : '';
      
      if (nextChar == insertedChar) {
        // Skip over the existing closing char
        return TextEditingValue(
          text: newText,
          selection: TextSelection.collapsed(offset: newSelection.start + 1),
        );
      }
    }

    // Handle Enter key between brackets - add indentation
    if (insertedChar == '\n') {
      return _handleNewline(oldValue, newValue, oldSelection.start);
    }

    return newValue;
  }

  TextEditingValue _handleNewline(
    TextEditingValue oldValue,
    TextEditingValue newValue,
    int cursorPos,
  ) {
    final oldText = oldValue.text;
    
    // Check if cursor is between matching brackets
    if (cursorPos > 0 && cursorPos < oldText.length) {
      final charBefore = oldText[cursorPos - 1];
      final charAfter = oldText[cursorPos];
      
      if (_pairs[charBefore] == charAfter) {
        // Insert newline with proper indentation
        final indent = _getIndent(oldText, cursorPos - 1);
        final updatedText = newValue.text.replaceRange(
          cursorPos,
          cursorPos,
          '\n$indent',
        );
        
        return TextEditingValue(
          text: updatedText,
          selection: TextSelection.collapsed(offset: cursorPos + 1 + indent.length),
        );
      }
    }
    
    return newValue;
  }

  String _getIndent(String text, int pos) {
    // Find the start of the current line
    int lineStart = pos;
    while (lineStart > 0 && text[lineStart - 1] != '\n') {
      lineStart--;
    }
    
    // Extract indentation from current line
    String indent = '';
    for (int i = lineStart; i < text.length && i <= pos; i++) {
      if (text[i] == ' ' || text[i] == '\t') {
        indent += text[i];
      } else {
        break;
      }
    }
    
    // Add one level of indentation (4 spaces)
    return '$indent    ';
  }

  bool _isWordChar(String char) {
    if (char.isEmpty) return false;
    final code = char.codeUnitAt(0);
    return (code >= 65 && code <= 90) || // A-Z
           (code >= 97 && code <= 122) || // a-z
           (code >= 48 && code <= 57) || // 0-9
           code == 95; // _
  }
}

/// Bracket pair colorization helper
class BracketPairColorizer {
  static const _pairs = {
    '(': ')',
    '[': ']',
    '{': '}',
  };

  static const _colors = [
    0xFFFF6B6B, // Red
    0xFF4ECDC4, // Teal
    0xFF45B7D1, // Blue
    0xFF96CEB4, // Green
    0xFFFFEAA7, // Yellow
    0xFFDDA0DD, // Plum
    0xFF98D8C8, // Mint
    0xFFF7DC6F, // Gold
  ];

  /// Get color for bracket at given depth
  static int colorForDepth(int depth) {
    return _colors[depth % _colors.length];
  }

  /// Check if character is an opening bracket
  static bool isOpeningBracket(String char) {
    return _pairs.containsKey(char);
  }

  /// Check if character is a closing bracket
  static bool isClosingBracket(String char) {
    return _pairs.containsValue(char);
  }

  /// Get matching bracket
  static String? matchingBracket(String char) {
    if (_pairs.containsKey(char)) return _pairs[char];
    final reverse = Map.fromEntries(_pairs.entries.map((e) => MapEntry(e.value, e.key)));
    return reverse[char];
  }
}