class DevServer {
  final int port;
  final String name;
  final DateTime startedAt;
  bool isAlive;

  DevServer({
    required this.port,
    required this.name,
    required this.startedAt,
    this.isAlive = false,
  });

  String get url => 'http://127.0.0.1:$port';

  Map<String, dynamic> toJson() => {
        'port': port,
        'name': name,
        'startedAt': startedAt.toIso8601String(),
      };

  factory DevServer.fromJson(Map<String, dynamic> json) => DevServer(
        port: json['port'] as int,
        name: json['name'] as String,
        startedAt: DateTime.parse(json['startedAt'] as String),
      );
}
