import 'package:b_code/execution/exec_events.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('chunk boundaries do not create blank lines', () {
    final lines = LineCollector();

    expect(lines.add('hel'), isEmpty);
    expect(lines.add('lo\nworld'), ['hello']);
    expect(lines.add('\n'), ['world']);
    expect(lines.add('par'), isEmpty);
    expect(lines.flush(), ['par']);
    expect(lines.flush(), isEmpty);
  });

  test('a newline-only chunk is one blank line', () {
    final lines = LineCollector();
    expect(lines.add('\n'), ['']);
  });
}
