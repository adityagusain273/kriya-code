class AutocompleteKind {
  static const int keyword = 0;
  static const int snippet = 1;
  static const int function_ = 2;
  static const int class_ = 3;
  static const int variable = 4;
  static const int module = 5;
}

class AutocompleteItem {
  final String label;
  final String insertText;
  final int kind;
  final String detail;

  const AutocompleteItem({
    required this.label,
    required this.insertText,
    required this.kind,
    this.detail = '',
  });

  @override
  bool operator ==(Object other) =>
      other is AutocompleteItem && other.label == label && other.insertText == insertText;

  @override
  int get hashCode => Object.hash(label, insertText);
}
