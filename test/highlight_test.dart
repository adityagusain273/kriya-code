// ignore_for_file: avoid_print, unused_import
import 'package:highlight/highlight.dart';
import 'package:highlight/languages/python.dart';

void main() {
  final res = highlight.parse('print("hello")', language: 'python');
  print('nodes: ${res.nodes}');
  for (var node in res.nodes!) {
    print('node: ${node.className}, val: "${node.value}", ch: ${node.children}');
    if (node.children != null) {
      for (var ch in node.children!) {
        print('  ch: ${ch.className}, val: "${ch.value}"');
      }
    }
  }
}
