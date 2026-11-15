import 'package:b_code/terminal/terminal_widget.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const home = '/data/data/com.termux/files/home';

  test('cd with no argument returns to the Termux home', () {
    expect(resolveTermuxCwd('$home/projects', '', home: home), home);
    expect(resolveTermuxCwd('$home/projects', '~', home: home), home);
  });

  test('relative paths resolve against the current directory', () {
    expect(resolveTermuxCwd(home, 'projects/demo', home: home), '$home/projects/demo');
    expect(resolveTermuxCwd('$home/projects', 'demo', home: home), '$home/projects/demo');
    expect(resolveTermuxCwd('$home/projects', '~/scratch', home: home), '$home/scratch');
    expect(resolveTermuxCwd('$home/projects', '..', home: home), home);
    expect(resolveTermuxCwd(home, './a/../b', home: home), '$home/b');
  });

  test('absolute paths are kept', () {
    expect(resolveTermuxCwd(home, '/sdcard/Download', home: home), '/sdcard/Download');
    expect(resolveTermuxCwd(home, '/sdcard/../tmp', home: home), '/tmp');
  });

  test('climbing above the filesystem root stops at the root', () {
    expect(resolveTermuxCwd('/tmp', '../../../..', home: home), '/');
  });
}
