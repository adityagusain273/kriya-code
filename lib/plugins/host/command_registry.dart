typedef CommandHandler = Future<void> Function(Map<String, Object?> args);

class CommandRegistry {
  final _commands = <String, CommandHandler>{};

  void register(String id, CommandHandler handler) {
    if (_commands.containsKey(id)) {
      throw StateError('Command already registered: $id');
    }
    _commands[id] = handler;
  }

  Future<bool> execute(String id, [Map<String, Object?> args = const {}]) async {
    final handler = _commands[id];
    if (handler == null) return false;
    await handler(args);
    return true;
  }

  bool exists(String id) => _commands.containsKey(id);

  List<String> get ids => List.unmodifiable(_commands.keys);
}
