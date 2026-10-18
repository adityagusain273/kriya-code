import 'package:highlight/highlight_core.dart';

import '../api/language_contribution.dart';

class LanguageRegistry {
  final _byId = <String, LanguageContribution>{};

  void register(LanguageContribution contribution) {
    if (_byId.containsKey(contribution.id)) return;
    _byId[contribution.id] = contribution;
  }

  LanguageContribution? byId(String id) => _byId[id];

  LanguageContribution? byFileName(String fileName) {
    for (final c in _byId.values) {
      if (c.matchesFile(fileName)) return c;
    }
    return null;
  }

  Mode? grammarFor(String fileName) => byFileName(fileName)?.grammar;

  List<LanguageContribution> get all =>
      List.unmodifiable(_byId.values.where((c) => c.fileExtensions.isNotEmpty));
}
