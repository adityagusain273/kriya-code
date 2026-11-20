import 'package:highlight/languages/cpp.dart';

import '../../api/extension.dart';
import '../../api/language_contribution.dart';
import '../../api/run_config.dart';

class CExtension extends BCodeExtension {
  static final LanguageContribution _contribution = LanguageContribution(
    id: 'c',
    name: 'C',
    fileExtensions: ['c', 'h'],
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
          '{runtimePath}/bin/clang',
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
  String get id => 'bcode.lang.c';

  @override
  String get name => 'C Language Pack';

  @override
  String get version => '1.0.0';

  @override
  Future<void> activate(ExtensionContext context) async {
    context.languages.register(_contribution);
  }

  @override
  Future<void> deactivate() async {}
}
