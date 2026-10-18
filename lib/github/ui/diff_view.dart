import 'package:flutter/material.dart';

class DiffViewPage extends StatelessWidget {
  final String path;
  final String patch;

  const DiffViewPage({super.key, required this.path, required this.patch});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(path.split('/').last)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final line in patch.split('\n'))
              Text(
                line,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  height: 1.45,
                  color: line.startsWith('+') && !line.startsWith('+++')
                      ? Colors.green.shade400
                      : line.startsWith('-') && !line.startsWith('---')
                          ? Colors.red.shade400
                          : line.startsWith('@@')
                              ? Colors.blue.shade300
                              : null,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
