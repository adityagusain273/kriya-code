import 'package:flutter/foundation.dart';

import '../../core/di.dart';
import '../../workspace/fs_service.dart';
import '../api/extension.dart';
import 'command_registry.dart';
import 'event_bus.dart';
import 'language_registry.dart';

class _DefaultContext implements ExtensionContext {
  @override
  final LanguageRegistry languages;
  @override
  final CommandRegistry commands;
  @override
  final BCodeEventBus events;
  @override
  final FsService fs;

  const _DefaultContext(this.languages, this.commands, this.events, this.fs);
}

class ExtensionRegistry {
  final _extensions = <BCodeExtension>[];
  late LanguageRegistry languageRegistry;
  late CommandRegistry commandRegistry;
  late BCodeEventBus eventBus;
  late FsService fsService;

  Future<void> loadAll(List<BCodeExtension> extensions) async {
    languageRegistry = LanguageRegistry();
    commandRegistry = CommandRegistry();
    eventBus = BCodeEventBus();
    fsService = sl.get<FsService>();
    for (final ext in extensions) {
      try {
        await ext.activate(
          _DefaultContext(languageRegistry, commandRegistry, eventBus, fsService),
        );
        _extensions.add(ext);
      } catch (e) {
        debugPrint('ExtensionRegistry: failed to activate ${ext.runtimeType}: $e');
      }
    }
  }

  List<BCodeExtension> get loaded => List.unmodifiable(_extensions);

  Future<void> dispose() async {
    for (final ext in _extensions.reversed) {
      try {
        await ext.deactivate();
      } catch (e) {
        debugPrint('ExtensionRegistry: failed to deactivate ${ext.runtimeType}: $e');
      }
    }
    await eventBus.dispose();
    _extensions.clear();
  }
}
