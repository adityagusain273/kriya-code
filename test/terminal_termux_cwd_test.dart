import 'package:kriya_code/terminal/terminal_widget.dart';
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

  test('parsePastedCommands handles comments and multiline commands', () {
    const input = '''
# Go
go run showcase_suite/08_go/main.go

# Rust
rustc showcase_suite/09_rust/main.rs -o rust_app && ./rust_app

# Ruby
ruby showcase_suite/11_ruby/main.rb
''';
    final commands = parsePastedCommands(input);
    expect(commands.length, 6);
    expect(commands[0], '# Go');
    expect(commands[1], 'go run showcase_suite/08_go/main.go');
    expect(commands[2], '# Rust');
    expect(commands[3], 'rustc showcase_suite/09_rust/main.rs -o rust_app && ./rust_app');
    expect(commands[4], '# Ruby');
    expect(commands[5], 'ruby showcase_suite/11_ruby/main.rb');
  });

  test('resetSessionForTesting resets buffer and cursor', () {
    TerminalWidget.resetSessionForTesting();
  });
}
