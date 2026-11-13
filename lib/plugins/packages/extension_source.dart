import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ExtensionCatalogEntry {
  final String id;
  final String name;
  final String version;
  final String description;
  final String author;
  final String download;
  final String homepage;
  final String source;

  const ExtensionCatalogEntry({
    required this.id,
    required this.name,
    required this.version,
    required this.description,
    required this.author,
    required this.download,
    required this.homepage,
    required this.source,
  });
}

class ExtensionBrowseResult {
  final List<ExtensionCatalogEntry> entries;
  final Map<String, String> errors;

  const ExtensionBrowseResult(this.entries, this.errors);
}

/// Reads extension indexes from URLs the user chooses.
///
/// There is no B Code server and no central account. A public extension is one
/// listed in an index JSON the author hosts (GitHub Pages, a gist, a company
/// intranet); a private one is simply not listed and is installed by file or
/// by an unlisted URL.
class ExtensionSourceService {
  static const defaultSource =
      'https://raw.githubusercontent.com/adityagusain273/b-code/main/extensions-index/index.json';
  static const defaultSources = <String>[defaultSource];
  static const _prefsKey = 'extension_sources';
  static const _seededKey = 'extension_seeded_defaults';
  static const maxIndexBytes = 1024 * 1024;

  final SharedPreferences prefs;
  final http.Client client;

  /// The defaults that are actually listed. A fresh install gets the whole
  /// list; an existing install gets whatever is new. Removing one writes the
  /// remaining list, so the removed default does not come back on the next
  /// launch until the user adds it again.
  final List<String> defaults;

  ExtensionSourceService({
    required this.prefs,
    http.Client? client,
    List<String>? defaults,
  })  : client = client ?? http.Client(),
        defaults = List.unmodifiable(defaults ?? defaultSources);

  List<String> get sources {
    final configured = prefs.getStringList(_prefsKey);
    if (configured == null) return defaults;
    return List.unmodifiable(configured);
  }

  /// Adds every default that has not been seeded yet. Called once at startup
  /// so an existing install picks up new official sources without resurrecting
  /// one the user removed.
  Future<void> seedDefaults() async {
    final seeded = prefs.getStringList(_seededKey) ?? const [];
    final missing =
        defaults.where((source) => !seeded.contains(source)).toList();
    if (missing.isEmpty) return;

    final list = sources.toList();
    for (final source in missing) {
      if (!list.contains(source)) list.add(source);
    }
    await prefs.setStringList(_prefsKey, list);
    await prefs.setStringList(_seededKey, [...seeded, ...missing]);
  }

  Future<void> addSource(String url) async {
    final normalized = _validSource(url);
    final list = sources.toList();
    if (!list.contains(normalized)) list.add(normalized);
    await prefs.setStringList(_prefsKey, list);
  }

  Future<void> removeSource(String url) async {
    final list = sources.toList()..remove(url);
    await prefs.setStringList(_prefsKey, list);
  }

  Future<ExtensionBrowseResult> browse() async {
    final entries = <String, ExtensionCatalogEntry>{};
    final errors = <String, String>{};

    await Future.wait(sources.map((source) async {
      try {
        for (final entry in await _fetch(source)) {
          entries.putIfAbsent(entry.id, () => entry);
        }
      } catch (error) {
        errors[source] = error.toString();
      }
    }));

    final list = entries.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return ExtensionBrowseResult(list, errors);
  }

  Future<List<ExtensionCatalogEntry>> _fetch(String source) async {
    final uri = Uri.parse(source);
    final request = http.Request('GET', uri);
    final response =
        await client.send(request).timeout(const Duration(seconds: 20));
    final finalUrl = response.request?.url;
    if (finalUrl != null && finalUrl.scheme != 'https') {
      throw StateError('redirected to a non-HTTPS URL');
    }
    if (response.statusCode != 200) {
      throw StateError('HTTP ${response.statusCode}');
    }

    final bytes = <int>[];
    await for (final chunk
        in response.stream.timeout(const Duration(seconds: 20))) {
      if (bytes.length + chunk.length > maxIndexBytes) {
        throw StateError('the index is larger than 1 MB');
      }
      bytes.addAll(chunk);
    }

    final decoded = jsonDecode(utf8.decode(bytes));
    final raw = decoded is Map ? decoded['extensions'] : decoded;
    if (raw is! List) {
      throw StateError('the index has no "extensions" list');
    }
    if (raw.length > 500) {
      throw StateError('the index lists more than 500 extensions');
    }

    final entries = <ExtensionCatalogEntry>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      final id = map['id']?.toString().trim() ?? '';
      final name = map['name']?.toString().trim() ?? '';
      final download = map['download']?.toString().trim() ?? '';
      if (id.isEmpty || name.isEmpty || download.isEmpty) continue;
      final resolved = Uri.tryParse(source)?.resolve(download);
      if (resolved == null || resolved.scheme != 'https') continue;
      entries.add(ExtensionCatalogEntry(
        id: id,
        name: name,
        version: map['version']?.toString() ?? '',
        description: map['description']?.toString() ?? '',
        author: map['author']?.toString() ?? '',
        download: resolved.toString(),
        homepage: map['homepage']?.toString() ?? '',
        source: source,
      ));
    }
    return entries;
  }

  String _validSource(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      throw ArgumentError('Extension sources must be full https:// URLs.');
    }
    return uri.toString();
  }
}
