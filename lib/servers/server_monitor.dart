import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dev_server.dart';

class ServerMonitor extends ChangeNotifier {
  static const _prefKey = 'dev_servers_v1';
  static const _autoDiscoverPorts = [3000, 4000, 5000, 8000, 8080, 8888, 9000, 4200, 3001, 8081];
  static const _probeTimeout = Duration(seconds: 1);
  static const _probeInterval = Duration(seconds: 10);

  final SharedPreferences _prefs;
  final _servers = <int, DevServer>{};
  Timer? _probeTimer;
  Timer? _initialTimer;
  bool _disposed = false;

  ServerMonitor(this._prefs) {
    _load();
    _startProbing();
  }

  List<DevServer> get servers => _servers.values.toList()
    ..sort((a, b) => a.port.compareTo(b.port));

  void addServer(int port, {String? name}) {
    if (_servers.containsKey(port)) return;
    _servers[port] = DevServer(
      port: port,
      name: name ?? 'localhost:$port',
      startedAt: DateTime.now(),
    );
    _save();
    _probeOne(_servers[port]!);
    notifyListeners();
  }

  void removeServer(int port) {
    _servers.remove(port);
    _save();
    notifyListeners();
  }

  void addLiveServer(int port) {
    addServer(port, name: 'Live Server');
  }

  void removeLiveServer(int port) {
    removeServer(port);
  }

  void _load() {
    final raw = _prefs.getString(_prefKey);
    if (raw == null) return;
    try {
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      for (final json in list) {
        final s = DevServer.fromJson(json);
        _servers[s.port] = s;
      }
    } catch (_) {}
  }

  void _save() {
    final list = _servers.values.map((s) => s.toJson()).toList();
    _prefs.setString(_prefKey, jsonEncode(list));
  }

  void _startProbing() {
    _probeTimer = Timer.periodic(_probeInterval, (_) => _probeAll());
    _initialTimer = Timer(const Duration(seconds: 2), _initialProbe);
  }

  Future<void> _initialProbe() async {
    await _probeAll();
    await _autoDiscover();
  }

  Future<void> _probeAll() async {
    if (_servers.isEmpty) return;
    bool changed = false;
    for (final server in _servers.values.toList()) {
      final alive = await _isPortOpen(server.port);
      if (_disposed) return;
      if (alive != server.isAlive) {
        server.isAlive = alive;
        changed = true;
      }
    }
    if (_disposed) return;
    if (changed) notifyListeners();
  }

  Future<void> _probeOne(DevServer server) async {
    final alive = await _isPortOpen(server.port);
    if (_disposed) return;
    if (alive != server.isAlive) {
      server.isAlive = alive;
      notifyListeners();
    }
  }

  Future<void> _autoDiscover() async {
    for (final port in _autoDiscoverPorts) {
      if (_servers.containsKey(port)) continue;
      final alive = await _isPortOpen(port);
      if (alive) {
        addServer(port);
      }
    }
  }

  Future<bool> _isPortOpen(int port) async {
    try {
      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        port,
        timeout: _probeTimeout,
      );
      await socket.close();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> refresh() async {
    await _probeAll();
    await _autoDiscover();
  }

  @override
  void dispose() {
    _disposed = true;
    _probeTimer?.cancel();
    _initialTimer?.cancel();
    super.dispose();
  }
}
