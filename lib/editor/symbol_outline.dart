import 'package:flutter/material.dart';

import '../lsp/outline_parser.dart';
import 'tab_manager.dart';

/// The document outline: every declaration in the active file, nested, with a
/// search box and a tap target that moves the caret.
///
/// A modal sheet rather than a permanent panel: on a phone a side panel would
/// take half the code away, and the outline is something a user opens for a few
/// seconds.
class SymbolOutlineSheet extends StatefulWidget {
  final EditorTab tab;

  const SymbolOutlineSheet({super.key, required this.tab});

  static Future<void> show(BuildContext context, EditorTab tab) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SymbolOutlineSheet(tab: tab),
    );
  }

  @override
  State<SymbolOutlineSheet> createState() => _SymbolOutlineSheetState();
}

class _SymbolOutlineSheetState extends State<SymbolOutlineSheet> {
  final _searchCtrl = TextEditingController();
  late List<OutlineSymbol> _symbols;

  @override
  void initState() {
    super.initState();
    _symbols = OutlineParser.parse(
      widget.tab.controller.text,
      widget.tab.languageId,
    );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<_OutlineRow> get _rows {
    final query = _searchCtrl.text.trim().toLowerCase();
    final rows = <_OutlineRow>[];
    void walk(List<OutlineSymbol> symbols, int depth) {
      for (final symbol in symbols) {
        if (query.isEmpty || symbol.name.toLowerCase().contains(query)) {
          rows.add(_OutlineRow(symbol, depth));
        }
        walk(symbol.children, depth + 1);
      }
    }

    walk(_symbols, 0);
    return rows;
  }

  void _open(OutlineSymbol symbol) {
    widget.tab.revealAt(symbol.offset);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rows = _rows;

    return FractionallySizedBox(
      heightFactor: 0.8,
      child: Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 4),
              child: Row(
                children: [
                  Icon(Icons.list_alt_outlined, size: 18, color: cs.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      autofocus: true,
                      decoration: const InputDecoration(
                        hintText: 'Search symbols in this file',
                        isDense: true,
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                      style: const TextStyle(fontSize: 16),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  if (_searchCtrl.text.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () => setState(() => _searchCtrl.clear()),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: rows.isEmpty
                  ? Center(
                      child: Text(
                        _symbols.isEmpty
                            ? 'No symbols in this file'
                            : 'No matches',
                        style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                      ),
                    )
                  : ListView.builder(
                      itemCount: rows.length,
                      padding: const EdgeInsets.only(bottom: 8),
                      itemBuilder: (context, i) {
                        final row = rows[i];
                        final symbol = row.symbol;
                        return ListTile(
                          dense: true,
                          visualDensity: VisualDensity.compact,
                          contentPadding: EdgeInsets.only(left: 12 + row.depth * 14, right: 12),
                          leading: Icon(
                            _iconFor(symbol.kind),
                            size: 16,
                            color: symbol.isContainer
                                ? cs.primary
                                : cs.onSurfaceVariant,
                          ),
                          title: Text(
                            symbol.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: symbol.isContainer
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                          subtitle: Text(
                            '${symbol.detail} · line ${symbol.line + 1}',
                            style: TextStyle(
                              fontSize: 11,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          onTap: () => _open(symbol),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  static IconData _iconFor(SymbolKind kind) => switch (kind) {
        SymbolKind.class_ => Icons.class_outlined,
        SymbolKind.method => Icons.subdirectory_arrow_right,
        SymbolKind.function => Icons.functions,
        SymbolKind.variable => Icons.data_object,
      };
}

class _OutlineRow {
  final OutlineSymbol symbol;
  final int depth;

  const _OutlineRow(this.symbol, this.depth);
}