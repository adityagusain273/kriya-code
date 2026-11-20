import 'package:highlight/languages/cpp.dart';

import '../../api/extension.dart';
import '../../api/language_contribution.dart';
import '../../api/run_config.dart';

class CppExtension extends BCodeExtension {
  static final LanguageContribution _contribution = LanguageContribution(
    id: 'cpp',
    name: 'C++',
    fileExtensions: ['cpp', 'cc', 'cxx', 'hpp', 'hh', 'h'],
    grammar: cpp,
    indentRules: const IndentRules(
      indentWidth: 4,
      blockOpeners: ['{'],
      blockClosers: ['}'],
    ),
    runConfig: const RunConfig(
      local: LocalTarget(
        runtimeId: 'clang',
        buildArgv: [
          '{runtimePath}/bin/clang++',
          '-std=c++17',
          '-isystem',
          '{runtimePath}/include/c++/v1',
          '-isystem',
          '{runtimePath}/include',
          '-isystem',
          '{runtimePath}/include/aarch64-linux-android',
          '-L{runtimePath}/lib',
          '{file}',
          '-o',
          '{outDir}/{name}.out',
        ],
        runArgv: ['{outDir}/{name}.out'],
      ),
    ),
  );

  @override
  String get id => 'bcode.lang.cpp';

  @override
  String get name => 'C++ Language Pack';

  @override
  String get version => '1.0.0';

  @override
  Future<void> activate(ExtensionContext context) async {
    context.languages.register(_contribution);
  }

  @override
  Future<void> deactivate() async {}
}
