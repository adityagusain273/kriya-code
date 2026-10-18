import 'package:flutter/material.dart';

import '../core/di.dart';
import '../plugins/host/extension_install_store.dart';
import 'mdi.dart';

class FileIconSpec {
  final IconData icon;
  final Color color;
  final List<Color>? gradient;

  const FileIconSpec(this.icon, this.color, {this.gradient});
}

class FileTypeIcon extends StatelessWidget {
  final FileIconSpec spec;
  final double size;

  const FileTypeIcon({super.key, required this.spec, this.size = 18});

  @override
  Widget build(BuildContext context) {
    final gradient = spec.gradient;
    if (gradient == null || gradient.length < 2) {
      return Icon(spec.icon, size: size, color: spec.color);
    }
    return ShaderMask(
      shaderCallback: (bounds) => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [gradient[0], gradient[0], gradient[1], gradient[1]],
        stops: const [0.0, 0.5, 0.5, 1.0],
      ).createShader(bounds),
      child: Icon(spec.icon, size: size, color: Colors.white),
    );
  }
}

const Color folderColor = Color(0xFFdcb67a);

final Map<String, FileIconSpec> _byFolderName = {
  'lib': const FileIconSpec(Mdi.folderOutline, Color(0xFF4CAF50)),
  'libs': const FileIconSpec(Mdi.folderOutline, Color(0xFF4CAF50)),
  'bin': const FileIconSpec(Mdi.folderOutline, Color(0xFFE91E63)),
  'include': const FileIconSpec(Mdi.folderOutline, Color(0xFF2196F3)),
  'templates': const FileIconSpec(Mdi.folderOutline, Color(0xFFFF9800)),
  '.git': const FileIconSpec(Mdi.git, Color(0xFFF05032)),
  '.github': const FileIconSpec(Mdi.folderOutline, Color(0xFFEAEAEA)),
  'node_modules': const FileIconSpec(Mdi.folderOutline, Color(0xFF8BC34A)),
  'src': const FileIconSpec(Mdi.folderOutline, Color(0xFF03A9F4)),
  'test': const FileIconSpec(Mdi.folderOutline, Color(0xFF8BC34A)),
  'assets': const FileIconSpec(Mdi.folderOutline, Color(0xFFFFC107)),
  'build': const FileIconSpec(Mdi.folderOutline, Color(0xFF9E9E9E)),
  '__pycache__': const FileIconSpec(Mdi.folderOutline, Color(0xFF9E9E9E)),
  'android': const FileIconSpec(Mdi.android, Color(0xFF3DDC84)),
  'ios': const FileIconSpec(Mdi.folderOutline, Color(0xFF9E9E9E)),
  'macos': const FileIconSpec(Mdi.folderOutline, Color(0xFF9E9E9E)),
  'linux': const FileIconSpec(Mdi.folderOutline, Color(0xFFFFC107)),
  'windows': const FileIconSpec(Mdi.folderOutline, Color(0xFF00A4EF)),
  'web': const FileIconSpec(Mdi.folderOutline, Color(0xFF2196F3)),
  'docs': const FileIconSpec(Mdi.folderOutline, Color(0xFF607D8B)),
  '.vscode': const FileIconSpec(Mdi.folderOutline, Color(0xFF007ACC)),
  '.husky': const FileIconSpec(Mdi.folderOutline, Color(0xFF8D6E63)),
  '.changesets': const FileIconSpec(Mdi.folderOutline, Color(0xFF1976D2)),
  '.devcontainer': const FileIconSpec(Mdi.folderOutline, Color(0xFF1976D2)),
  'api': const FileIconSpec(Mdi.folderOutline, Color(0xFFFFC107)),
  'architecture': const FileIconSpec(Mdi.folderOutline, Color(0xFF607D8B)),
  'guides': const FileIconSpec(Mdi.folderOutline, Color(0xFF607D8B)),
  'issue_template': const FileIconSpec(Mdi.folderOutline, Color(0xFFE57373)),
  'pull_request_template': const FileIconSpec(Mdi.folderOutline, Color(0xFFE57373)),
  'workflows': const FileIconSpec(Mdi.folderOutline, Color(0xFF64B5F6)),
  'scripts': const FileIconSpec(Mdi.folderOutline, Color(0xFFFFCA28)),
  'dist': const FileIconSpec(Mdi.folderOutline, Color(0xFF8D6E63)),
  'public': const FileIconSpec(Mdi.folderOutline, Color(0xFF4DB6AC)),
  'auto-assign': const FileIconSpec(Mdi.folderOutline, Color(0xFF90A4AE)),
  'dependabot': const FileIconSpec(Mdi.folderOutline, Color(0xFF1976D2)),
  'first-time-contributor': const FileIconSpec(Mdi.folderOutline, Color(0xFF90A4AE)),
  'labeler': const FileIconSpec(Mdi.folderOutline, Color(0xFF90A4AE)),
  'stale': const FileIconSpec(Mdi.folderOutline, Color(0xFF90A4AE)),
};

bool _useMaterialIcons() {
  try {
    return sl<ExtensionInstallStore>().isInstalled('bcode.icons.material');
  } catch (_) {
    return false;
  }
}

FileIconSpec folderSpec(String name, bool expanded) {
  if (_useMaterialIcons()) {
    final customSpec = _byFolderName[name.toLowerCase()];
    if (customSpec != null) {
      if (expanded && customSpec.icon == Mdi.folderOutline) {
        return FileIconSpec(Mdi.folderOpenOutline, customSpec.color, gradient: customSpec.gradient);
      }
      return customSpec;
    }
  }
  return FileIconSpec(
    expanded ? Mdi.folderOpenOutline : Mdi.folderOutline, 
    folderColor,
  );
}

final Map<String, FileIconSpec> _byExt = {
  'dart': const FileIconSpec(Icons.flutter_dash, Color(0xFF0175C2),
      gradient: [Color(0xFF13B9FD), Color(0xFF0175C2)]),
  'py': FileIconSpec(Mdi.languagePython, Color(0xFFFFCA28),
      gradient: [Color(0xFF4B8BBE), Color(0xFFFFD43B)]),
  'pyw': FileIconSpec(Mdi.languagePython, Color(0xFFFFCA28),
      gradient: [Color(0xFF4B8BBE), Color(0xFFFFD43B)]),
  'js': const FileIconSpec(Mdi.languageJavascript, Color(0xFFF7DF1E)),
  'mjs': const FileIconSpec(Mdi.languageJavascript, Color(0xFFF7DF1E)),
  'cjs': const FileIconSpec(Mdi.languageJavascript, Color(0xFFF7DF1E)),
  'ts': const FileIconSpec(Mdi.languageTypescript, Color(0xFF3178C6)),
  'tsx': const FileIconSpec(Mdi.languageTypescript, Color(0xFF3178C6)),
  'html': const FileIconSpec(Mdi.languageHtml5, Color(0xFFE34F26),
      gradient: [Color(0xFFF16529), Color(0xFFE34F26)]),
  'htm': const FileIconSpec(Mdi.languageHtml5, Color(0xFFE34F26),
      gradient: [Color(0xFFF16529), Color(0xFFE34F26)]),
  'css': const FileIconSpec(Mdi.languageCss3, Color(0xFF1572B6),
      gradient: [Color(0xFF33A9DC), Color(0xFF1572B6)]),
  'scss': const FileIconSpec(Mdi.languageCss3, Color(0xFFCD6799),
      gradient: [Color(0xFFDB7093), Color(0xFFA8557E)]),
  'sass': const FileIconSpec(Mdi.languageCss3, Color(0xFFCD6799),
      gradient: [Color(0xFFDB7093), Color(0xFFA8557E)]),
  'less': const FileIconSpec(Mdi.languageCss3, Color(0xFF448AFF)),
  'json': const FileIconSpec(Mdi.codeJson, Color(0xFFFDD835)),
  'jsonc': const FileIconSpec(Mdi.codeJson, Color(0xFFFDD835)),
  'yaml': const FileIconSpec(Mdi.codeBraces, Color(0xFFEF5350)),
  'yml': const FileIconSpec(Mdi.codeBraces, Color(0xFFEF5350)),
  'xml': const FileIconSpec(Mdi.xml, Color(0xFFF57C00),
      gradient: [Color(0xFFFFB74D), Color(0xFFF57C00)]),
  'iml': const FileIconSpec(Mdi.xml, Color(0xFFFE2857),
      gradient: [Color(0xFFFE2857), Color(0xFFFDB60D)]),
  'kt': const FileIconSpec(Mdi.languageKotlin, Color(0xFF7F52FF),
      gradient: [Color(0xFFE44857), Color(0xFF7F52FF)]),
  'kts': const FileIconSpec(Mdi.languageKotlin, Color(0xFF7F52FF),
      gradient: [Color(0xFFE44857), Color(0xFF7F52FF)]),
  'java': const FileIconSpec(Mdi.languageJava, Color(0xFFE76F00),
      gradient: [Color(0xFFE76F00), Color(0xFF5382A1)]),
  'class': const FileIconSpec(Mdi.languageJava, Color(0xFFE76F00),
      gradient: [Color(0xFFE76F00), Color(0xFF5382A1)]),
  'jar': const FileIconSpec(Mdi.languageJava, Color(0xFFE76F00),
      gradient: [Color(0xFFE76F00), Color(0xFF5382A1)]),
  'c': const FileIconSpec(Mdi.languageC, Color(0xFF00599C),
      gradient: [Color(0xFF659AD2), Color(0xFF00599C)]),
  'h': const FileIconSpec(Mdi.languageC, Color(0xFF00599C),
      gradient: [Color(0xFF659AD2), Color(0xFF00599C)]),
  'cpp': const FileIconSpec(Mdi.languageCpp, Color(0xFF00599C),
      gradient: [Color(0xFF659AD2), Color(0xFF004482)]),
  'cc': const FileIconSpec(Mdi.languageCpp, Color(0xFF00599C),
      gradient: [Color(0xFF659AD2), Color(0xFF004482)]),
  'cxx': const FileIconSpec(Mdi.languageCpp, Color(0xFF00599C),
      gradient: [Color(0xFF659AD2), Color(0xFF004482)]),
  'hpp': const FileIconSpec(Mdi.languageCpp, Color(0xFF00599C),
      gradient: [Color(0xFF659AD2), Color(0xFF004482)]),
  'hh': const FileIconSpec(Mdi.languageCpp, Color(0xFF00599C),
      gradient: [Color(0xFF659AD2), Color(0xFF004482)]),
  'cs': const FileIconSpec(Mdi.languageCsharp, Color(0xFF68217A),
      gradient: [Color(0xFF9B4F96), Color(0xFF68217A)]),
  'go': const FileIconSpec(Mdi.languageGo, Color(0xFF00ADD8)),
  'rs': const FileIconSpec(Mdi.languageRust, Color(0xFFF74C00),
      gradient: [Color(0xFFF74C00), Color(0xFF37474F)]),
  'rb': const FileIconSpec(Mdi.languageRuby, Color(0xFFCC342D),
      gradient: [Color(0xFFE9573F), Color(0xFF9B111E)]),
  'php': const FileIconSpec(Mdi.languagePhp, Color(0xFF777BB4),
      gradient: [Color(0xFF8892BF), Color(0xFF4F5B93)]),
  'swift': const FileIconSpec(Mdi.languageSwift, Color(0xFFF05138),
      gradient: [Color(0xFFFBA43C), Color(0xFFF05138)]),
  'r': const FileIconSpec(Mdi.languageR, Color(0xFF276DC3)),
  'lua': const FileIconSpec(Mdi.applicationBracketsOutline, Color(0xFF6C8FD0)),
  'sh': const FileIconSpec(Mdi.bash, Color(0xFF89E051)),
  'bash': const FileIconSpec(Mdi.bash, Color(0xFF89E051)),
  'zsh': const FileIconSpec(Mdi.bash, Color(0xFF89E051)),
  'bat': const FileIconSpec(Mdi.console, Color(0xFFFFD54F)),
  'cmd': const FileIconSpec(Mdi.console, Color(0xFFFFD54F)),
  'ps1': const FileIconSpec(Mdi.powershell, Color(0xFF5391FE),
      gradient: [Color(0xFF5391FE), Color(0xFF2E4A7D)]),
  'md': const FileIconSpec(Mdi.languageMarkdown, Color(0xFF64B5F6)),
  'mdx': const FileIconSpec(Mdi.languageMarkdown, Color(0xFF64B5F6)),
  'txt': const FileIconSpec(Mdi.fileDocumentOutline, Color(0xFF64B5F6)),
  'log': const FileIconSpec(Mdi.fileDocumentOutline, Color(0xFF9E9E9E)),
  'properties': const FileIconSpec(Mdi.cogOutline, Color(0xFF90A4AE)),
  'cfg': const FileIconSpec(Mdi.cogOutline, Color(0xFF90A4AE)),
  'conf': const FileIconSpec(Mdi.cogOutline, Color(0xFF90A4AE)),
  'ini': const FileIconSpec(Mdi.cogOutline, Color(0xFF90A4AE)),
  'toml': const FileIconSpec(Mdi.cogOutline, Color(0xFFE0B050)),
  'lock': const FileIconSpec(Mdi.lockOutline, Color(0xFFE2C08D)),
  'bin': const FileIconSpec(Mdi.memory, Color(0xFF90A4AE)),
  'dat': const FileIconSpec(Mdi.memory, Color(0xFF90A4AE)),
  'cmake': const FileIconSpec(Mdi.elephant, Color(0xFF26A69A)),
  'svg': const FileIconSpec(Mdi.fileImageOutline, Color(0xFFFFB74D)),
  'png': const FileIconSpec(Mdi.fileImageOutline, Color(0xFFBA68C8)),
  'jpg': const FileIconSpec(Mdi.fileImageOutline, Color(0xFFBA68C8)),
  'jpeg': const FileIconSpec(Mdi.fileImageOutline, Color(0xFFBA68C8)),
  'gif': const FileIconSpec(Mdi.fileImageOutline, Color(0xFFBA68C8)),
  'webp': const FileIconSpec(Mdi.fileImageOutline, Color(0xFFBA68C8)),
  'bmp': const FileIconSpec(Mdi.fileImageOutline, Color(0xFFBA68C8)),
  'ico': const FileIconSpec(Mdi.fileImageOutline, Color(0xFFBA68C8)),
  'heic': const FileIconSpec(Mdi.fileImageOutline, Color(0xFFBA68C8)),
  'mp3': const FileIconSpec(Mdi.musicNote, Color(0xFFF06292)),
  'wav': const FileIconSpec(Mdi.musicNote, Color(0xFFF06292)),
  'flac': const FileIconSpec(Mdi.musicNote, Color(0xFFF06292)),
  'ogg': const FileIconSpec(Mdi.musicNote, Color(0xFFF06292)),
  'm4a': const FileIconSpec(Mdi.musicNote, Color(0xFFF06292)),
  'mp4': const FileIconSpec(Mdi.filmstrip, Color(0xFFEF5350)),
  'mkv': const FileIconSpec(Mdi.filmstrip, Color(0xFFEF5350)),
  'avi': const FileIconSpec(Mdi.filmstrip, Color(0xFFEF5350)),
  'mov': const FileIconSpec(Mdi.filmstrip, Color(0xFFEF5350)),
  'webm': const FileIconSpec(Mdi.filmstrip, Color(0xFFEF5350)),
  'pdf': const FileIconSpec(Mdi.filePdfBox, Color(0xFFEF5350)),
  'doc': const FileIconSpec(Mdi.fileWordOutline, Color(0xFF42A5F5)),
  'docx': const FileIconSpec(Mdi.fileWordOutline, Color(0xFF42A5F5)),
  'xls': const FileIconSpec(Mdi.fileTableOutline, Color(0xFF66BB6A)),
  'xlsx': const FileIconSpec(Mdi.fileTableOutline, Color(0xFF66BB6A)),
  'csv': const FileIconSpec(Mdi.fileTableOutline, Color(0xFF66BB6A)),
  'tsv': const FileIconSpec(Mdi.fileTableOutline, Color(0xFF66BB6A)),
  'zip': const FileIconSpec(Mdi.zipBoxOutline, Color(0xFFFFB74D)),
  'rar': const FileIconSpec(Mdi.zipBoxOutline, Color(0xFFFFB74D)),
  '7z': const FileIconSpec(Mdi.zipBoxOutline, Color(0xFFFFB74D)),
  'tar': const FileIconSpec(Mdi.zipBoxOutline, Color(0xFFFFB74D)),
  'gz': const FileIconSpec(Mdi.zipBoxOutline, Color(0xFFFFB74D)),
  'bz2': const FileIconSpec(Mdi.zipBoxOutline, Color(0xFFFFB74D)),
  'xz': const FileIconSpec(Mdi.zipBoxOutline, Color(0xFFFFB74D)),
  'apk': const FileIconSpec(Mdi.android, Color(0xFF3DDC84)),
  'exe': const FileIconSpec(Mdi.memory, Color(0xFF90A4AE)),
  'dll': const FileIconSpec(Mdi.memory, Color(0xFF90A4AE)),
  'so': const FileIconSpec(Mdi.memory, Color(0xFF90A4AE)),
  'sql': const FileIconSpec(Mdi.database, Color(0xFFFFA726)),
  'db': const FileIconSpec(Mdi.database, Color(0xFF4DB6AC)),
  'sqlite': const FileIconSpec(Mdi.database, Color(0xFF4DB6AC)),
  'sqlite3': const FileIconSpec(Mdi.database, Color(0xFF4DB6AC)),
  'ipynb': const FileIconSpec(Mdi.flaskOutline, Color(0xFFF37726)),
};

final Map<String, FileIconSpec> _exactMatchIcons = {
  'gradlew': const FileIconSpec(Mdi.console, Color(0xFF26A69A)),
  'gradlew.bat': const FileIconSpec(Mdi.console, Color(0xFF26A69A)),
  'pubspec.yaml': const FileIconSpec(Icons.flutter_dash, Color(0xFF0175C2), gradient: [Color(0xFF13B9FD), Color(0xFF0175C2)]),
  'pubspec.lock': const FileIconSpec(Mdi.lockOutline, Color(0xFFE2C08D)),
  'cmakelists.txt': const FileIconSpec(Mdi.elephant, Color(0xFF26A69A)),
  'makefile': const FileIconSpec(Mdi.elephant, Color(0xFF26A69A)),
  'license': const FileIconSpec(Mdi.fileCertificateOutline, Color(0xFFB0BEC5)),
  'licence': const FileIconSpec(Mdi.fileCertificateOutline, Color(0xFFB0BEC5)),
  'readme.md': const FileIconSpec(Icons.info_outline, Color(0xFF64B5F6)),
  'changelog.md': const FileIconSpec(Icons.format_list_bulleted, Color(0xFF81C784)),
  'contributing.md': const FileIconSpec(Icons.favorite_border, Color(0xFFE57373)),
  'dockerfile': const FileIconSpec(Mdi.fileOutline, Color(0xFF2496ED)),
  'docker-compose.yml': const FileIconSpec(Mdi.fileOutline, Color(0xFF2496ED)),
  'docker-compose.yaml': const FileIconSpec(Mdi.fileOutline, Color(0xFF2496ED)),
  'package.json': const FileIconSpec(Mdi.fileOutline, Color(0xFF8BC34A)),
  'package-lock.json': const FileIconSpec(Mdi.lockOutline, Color(0xFF8BC34A)),
  'yarn.lock': const FileIconSpec(Mdi.lockOutline, Color(0xFF2188B6)),
  'pnpm-lock.yaml': const FileIconSpec(Mdi.lockOutline, Color(0xFFF69220)),
  'tsconfig.json': const FileIconSpec(Mdi.codeJson, Color(0xFF3178C6)),
  'jsconfig.json': const FileIconSpec(Mdi.codeJson, Color(0xFFF7DF1E)),
  '.eslintrc': const FileIconSpec(Mdi.fileOutline, Color(0xFF4B32C3)),
  '.eslintignore': const FileIconSpec(Mdi.fileOutline, Color(0xFF4B32C3)),
  '.prettierrc': const FileIconSpec(Mdi.fileOutline, Color(0xFFF7B93E)),
  '.prettierignore': const FileIconSpec(Mdi.fileOutline, Color(0xFFF7B93E)),
  '.editorconfig': const FileIconSpec(Mdi.cogOutline, Color(0xFFFFF7EB)),
  '.gitignore': const FileIconSpec(Mdi.git, Color(0xFFF05032)),
  '.gitattributes': const FileIconSpec(Mdi.git, Color(0xFFF05032)),
  '.gitmodules': const FileIconSpec(Mdi.git, Color(0xFFF05032)),
  '.npmrc': const FileIconSpec(Mdi.fileOutline, Color(0xFFCB3837)),
  '.nvmrc': const FileIconSpec(Mdi.fileOutline, Color(0xFF8BC34A)),
  '.babelrc': const FileIconSpec(Mdi.fileOutline, Color(0xFFF9DC3E)),
  'codeowners': const FileIconSpec(Icons.people_outline, Color(0xFF90A4AE)),
  'build': const FileIconSpec(Mdi.fileDocumentOutline, Color(0xFF90A4AE)),
  'buck': const FileIconSpec(Mdi.fileDocumentOutline, Color(0xFF90A4AE)),
  'cargo.lock': const FileIconSpec(Mdi.lockOutline, Color(0xFFE2C08D)),
  'cargo.toml': const FileIconSpec(Mdi.cogOutline, Color(0xFFE2C08D)),
  'gemfile': const FileIconSpec(Mdi.languageRuby, Color(0xFFCC342D)),
  'gemfile.lock': const FileIconSpec(Mdi.lockOutline, Color(0xFFCC342D)),
  'go.mod': const FileIconSpec(Mdi.languageGo, Color(0xFF00ADD8)),
  'go.sum': const FileIconSpec(Mdi.languageGo, Color(0xFF00ADD8)),
  'go.work': const FileIconSpec(Mdi.languageGo, Color(0xFF00ADD8)),
  'pipfile': const FileIconSpec(Mdi.languagePython, Color(0xFFFFCA28)),
  'pipfile.lock': const FileIconSpec(Mdi.lockOutline, Color(0xFFFFCA28)),
  'poetry.lock': const FileIconSpec(Mdi.lockOutline, Color(0xFF4B8BBE)),
  'poetry.toml': const FileIconSpec(Mdi.cogOutline, Color(0xFF4B8BBE)),
  'podfile': const FileIconSpec(Mdi.fileOutline, Color(0xFFF05138)),
  'podfile.lock': const FileIconSpec(Mdi.lockOutline, Color(0xFFF05138)),
  'package.swift': const FileIconSpec(Mdi.languageSwift, Color(0xFFF05138)),
  'package.resolved': const FileIconSpec(Mdi.lockOutline, Color(0xFFF05138)),
  'mix.exs': const FileIconSpec(Mdi.fileOutline, Color(0xFF4E2A8E)),
  'mix.lock': const FileIconSpec(Mdi.lockOutline, Color(0xFF4E2A8E)),
  'pom.xml': const FileIconSpec(Mdi.fileOutline, Color(0xFFC71A22)),
  'workspace': const FileIconSpec(Mdi.fileDocumentOutline, Color(0xFF90A4AE)),
};

FileIconSpec fileSpec(String fileName) {
  if (!_useMaterialIcons()) {
    return const FileIconSpec(Mdi.fileOutline, Color(0xFF90A4AE));
  }
  var name = fileName.toLowerCase();
  final slash = name.lastIndexOf('/');
  if (slash >= 0) name = name.substring(slash + 1);
  
  if (_exactMatchIcons.containsKey(name)) {
    return _exactMatchIcons[name]!;
  }

  if (name.endsWith('.example')) {
    name = name.substring(0, name.length - '.example'.length);
    if (_exactMatchIcons.containsKey(name)) {
      return _exactMatchIcons[name]!;
    }
  }
  
  if (name.startsWith('.git')) {
    return const FileIconSpec(Mdi.git, Color(0xFFF05032));
  }
  if (name == '.env' || name.startsWith('.env.')) {
    return const FileIconSpec(Mdi.cogOutline, Color(0xFF9CCC65));
  }
  if (name.contains('eslint')) {
    return const FileIconSpec(Mdi.fileOutline, Color(0xFF4B32C3));
  }
  if (name.contains('prettier')) {
    return const FileIconSpec(Mdi.fileOutline, Color(0xFFF7B93E));
  }
  if (name.contains('stylelint')) {
    return const FileIconSpec(Icons.palette_outlined, Color(0xFF000000));
  }
  if (name.contains('commitlint') || name.contains('czrc')) {
    return const FileIconSpec(Icons.check_circle_outline, Color(0xFF81C784));
  }
  if (name.contains('dependabot')) {
    return const FileIconSpec(Mdi.fileOutline, Color(0xFF1976D2));
  }
  if (name.contains('husky')) {
    return const FileIconSpec(Icons.pets, Color(0xFF8D6E63));
  }
  if (name.contains('lintstaged')) {
    return const FileIconSpec(Icons.playlist_add_check, Color(0xFF90A4AE));
  }
  if (name.contains('markdownlint')) {
    return const FileIconSpec(Mdi.languageMarkdown, Color(0xFF64B5F6));
  }
  if (name.contains('semanticrelease') || name.contains('releaserc')) {
    return const FileIconSpec(Icons.rocket_launch_outlined, Color(0xFFE57373));
  }
  if (name.contains('snyk')) {
    return const FileIconSpec(Icons.security_outlined, Color(0xFF4C4A73));
  }
  if (name.contains('vite.config')) {
    return const FileIconSpec(Icons.flash_on, Color(0xFF646CFF));
  }
  if (name.contains('webpack.config')) {
    return const FileIconSpec(Icons.view_in_ar_outlined, Color(0xFF8DD6F9));
  }
  if (name.contains('rollup.config')) {
    return const FileIconSpec(Icons.layers_outlined, Color(0xFFEF3335));
  }
  if (name.contains('esbuild.config')) {
    return const FileIconSpec(Icons.bolt, Color(0xFFFFC107));
  }
  if (name.contains('parcel.config')) {
    return const FileIconSpec(Icons.inventory_2_outlined, Color(0xFF8A9A5B));
  }
  if (name.startsWith('requirements')) {
    return const FileIconSpec(Mdi.languagePython, Color(0xFFFFCA28));
  }
  
  if (name.endsWith('.gradle') || name.endsWith('.gradle.kts')) {
    return const FileIconSpec(Mdi.elephant, Color(0xFF26A69A));
  }
  
  final dot = name.lastIndexOf('.');
  if (dot < 0) {
    return FileIconSpec(Mdi.fileDocumentOutline, const Color(0xFF90A4AE));
  }
  return _byExt[name.substring(dot + 1)] ?? const FileIconSpec(Mdi.fileOutline, Color(0xFF78909C));
}
