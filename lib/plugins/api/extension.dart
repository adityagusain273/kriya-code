import '../host/command_registry.dart';
import '../host/event_bus.dart';
import '../host/language_registry.dart';
import '../../workspace/fs_service.dart';

abstract class ExtensionContext {
  LanguageRegistry get languages;
  CommandRegistry get commands;
  BCodeEventBus get events;
  FsService get fs;
}

abstract class BCodeExtension {
  String get id;
  String get name;
  String get version;

  Future<void> activate(ExtensionContext context);
  Future<void> deactivate();
}
