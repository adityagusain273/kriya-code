import 'package:kriya_code/workspace/mdi.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Mdi defines valid git and github icons', () {
    expect(Mdi.git.fontFamily, 'Material Design Icons');
    expect(Mdi.git.codePoint, 0xf02a2);

    expect(Mdi.github.fontFamily, 'Material Design Icons');
    expect(Mdi.github.codePoint, 0xf02a4);
  });
}
