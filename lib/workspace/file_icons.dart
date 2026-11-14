import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../core/di.dart';
import '../plugins/host/extension_install_store.dart';
import 'mdi.dart';

class FileIconSpec {
  final IconData? icon;
  final String? asset;
  final Color color;

  const FileIconSpec(IconData this.icon, this.color) : asset = null;
  const FileIconSpec.asset(String this.asset)
      : icon = null,
        color = Colors.transparent;
}

class FileTypeIcon extends StatelessWidget {
  final FileIconSpec spec;
  final double size;

  const FileTypeIcon({super.key, required this.spec, this.size = 18});

  @override
  Widget build(BuildContext context) {
    final asset = spec.asset;
    if (asset != null) {
      return SvgPicture.asset(asset, width: size, height: size);
    }
    return Icon(spec.icon, size: size, color: spec.color);
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
        return FileIconSpec(Mdi.folderOpenOutline, customSpec.color);
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
  'dart': const FileIconSpec.asset('assets/icons/dart.svg'),
  'py': const FileIconSpec.asset('assets/icons/python.svg'),
  'pyw': const FileIconSpec.asset('assets/icons/python.svg'),
  'js': const FileIconSpec.asset('assets/icons/javascript.svg'),
  'mjs': const FileIconSpec.asset('assets/icons/javascript.svg'),
  'cjs': const FileIconSpec.asset('assets/icons/javascript.svg'),
  'jsx': const FileIconSpec.asset('assets/icons/react.svg'),
  'ts': const FileIconSpec.asset('assets/icons/typescript.svg'),
  'tsx': const FileIconSpec.asset('assets/icons/react_ts.svg'),
  'html': const FileIconSpec.asset('assets/icons/html.svg'),
  'htm': const FileIconSpec.asset('assets/icons/html.svg'),
  'css': const FileIconSpec.asset('assets/icons/css.svg'),
  'scss': const FileIconSpec.asset('assets/icons/sass.svg'),
  'sass': const FileIconSpec.asset('assets/icons/sass.svg'),
  'less': const FileIconSpec.asset('assets/icons/less.svg'),
  'json': const FileIconSpec.asset('assets/icons/json.svg'),
  'jsonc': const FileIconSpec.asset('assets/icons/json.svg'),
  'yaml': const FileIconSpec.asset('assets/icons/yaml.svg'),
  'yml': const FileIconSpec.asset('assets/icons/yaml.svg'),
  'xml': const FileIconSpec.asset('assets/icons/xml.svg'),
  'iml': const FileIconSpec.asset('assets/icons/xml.svg'),
  'kt': const FileIconSpec.asset('assets/icons/kotlin.svg'),
  'kts': const FileIconSpec.asset('assets/icons/kotlin.svg'),
  'java': const FileIconSpec.asset('assets/icons/java.svg'),
  'class': const FileIconSpec.asset('assets/icons/javaclass.svg'),
  'jar': const FileIconSpec.asset('assets/icons/jar.svg'),
  'c': const FileIconSpec.asset('assets/icons/c.svg'),
  'h': const FileIconSpec.asset('assets/icons/h.svg'),
  'cpp': const FileIconSpec.asset('assets/icons/cpp.svg'),
  'cc': const FileIconSpec.asset('assets/icons/cpp.svg'),
  'cxx': const FileIconSpec.asset('assets/icons/cpp.svg'),
  'hpp': const FileIconSpec.asset('assets/icons/hpp.svg'),
  'hh': const FileIconSpec.asset('assets/icons/hpp.svg'),
  'cs': const FileIconSpec.asset('assets/icons/csharp.svg'),
  'go': const FileIconSpec.asset('assets/icons/go.svg'),
  'rs': const FileIconSpec.asset('assets/icons/rust.svg'),
  'rb': const FileIconSpec.asset('assets/icons/ruby.svg'),
  'php': const FileIconSpec.asset('assets/icons/php.svg'),
  'swift': const FileIconSpec.asset('assets/icons/swift.svg'),
  'r': const FileIconSpec.asset('assets/icons/r.svg'),
  'lua': const FileIconSpec.asset('assets/icons/lua.svg'),
  'sh': const FileIconSpec.asset('assets/icons/console.svg'),
  'bash': const FileIconSpec.asset('assets/icons/console.svg'),
  'zsh': const FileIconSpec.asset('assets/icons/console.svg'),
  'bat': const FileIconSpec.asset('assets/icons/console.svg'),
  'cmd': const FileIconSpec.asset('assets/icons/console.svg'),
  'ps1': const FileIconSpec.asset('assets/icons/powershell.svg'),
  'md': const FileIconSpec.asset('assets/icons/markdown.svg'),
  'mdx': const FileIconSpec.asset('assets/icons/mdx.svg'),
  'txt': const FileIconSpec.asset('assets/icons/document.svg'),
  'log': const FileIconSpec.asset('assets/icons/log.svg'),
  'properties': const FileIconSpec.asset('assets/icons/settings.svg'),
  'cfg': const FileIconSpec.asset('assets/icons/settings.svg'),
  'conf': const FileIconSpec.asset('assets/icons/settings.svg'),
  'ini': const FileIconSpec.asset('assets/icons/settings.svg'),
  'toml': const FileIconSpec.asset('assets/icons/toml.svg'),
  'lock': const FileIconSpec.asset('assets/icons/lock.svg'),
  'bin': const FileIconSpec.asset('assets/icons/hex.svg'),
  'dat': const FileIconSpec.asset('assets/icons/hex.svg'),
  'cmake': const FileIconSpec.asset('assets/icons/cmake.svg'),
  'svg': const FileIconSpec.asset('assets/icons/svg.svg'),
  'png': const FileIconSpec.asset('assets/icons/image.svg'),
  'jpg': const FileIconSpec.asset('assets/icons/image.svg'),
  'jpeg': const FileIconSpec.asset('assets/icons/image.svg'),
  'gif': const FileIconSpec.asset('assets/icons/image.svg'),
  'webp': const FileIconSpec.asset('assets/icons/image.svg'),
  'bmp': const FileIconSpec.asset('assets/icons/image.svg'),
  'ico': const FileIconSpec.asset('assets/icons/image.svg'),
  'heic': const FileIconSpec.asset('assets/icons/image.svg'),
  'mp3': const FileIconSpec.asset('assets/icons/audio.svg'),
  'wav': const FileIconSpec.asset('assets/icons/audio.svg'),
  'flac': const FileIconSpec.asset('assets/icons/audio.svg'),
  'ogg': const FileIconSpec.asset('assets/icons/audio.svg'),
  'm4a': const FileIconSpec.asset('assets/icons/audio.svg'),
  'mp4': const FileIconSpec.asset('assets/icons/video.svg'),
  'mkv': const FileIconSpec.asset('assets/icons/video.svg'),
  'avi': const FileIconSpec.asset('assets/icons/video.svg'),
  'mov': const FileIconSpec.asset('assets/icons/video.svg'),
  'webm': const FileIconSpec.asset('assets/icons/video.svg'),
  'pdf': const FileIconSpec.asset('assets/icons/pdf.svg'),
  'doc': const FileIconSpec.asset('assets/icons/word.svg'),
  'docx': const FileIconSpec.asset('assets/icons/word.svg'),
  'xls': const FileIconSpec.asset('assets/icons/table.svg'),
  'xlsx': const FileIconSpec.asset('assets/icons/table.svg'),
  'csv': const FileIconSpec.asset('assets/icons/table.svg'),
  'tsv': const FileIconSpec.asset('assets/icons/table.svg'),
  'zip': const FileIconSpec.asset('assets/icons/zip.svg'),
  'rar': const FileIconSpec.asset('assets/icons/zip.svg'),
  '7z': const FileIconSpec.asset('assets/icons/zip.svg'),
  'tar': const FileIconSpec.asset('assets/icons/zip.svg'),
  'gz': const FileIconSpec.asset('assets/icons/zip.svg'),
  'bz2': const FileIconSpec.asset('assets/icons/zip.svg'),
  'xz': const FileIconSpec.asset('assets/icons/zip.svg'),
  'apk': const FileIconSpec.asset('assets/icons/android.svg'),
  'exe': const FileIconSpec.asset('assets/icons/exe.svg'),
  'dll': const FileIconSpec.asset('assets/icons/dll.svg'),
  'so': const FileIconSpec.asset('assets/icons/dll.svg'),
  'sql': const FileIconSpec.asset('assets/icons/database.svg'),
  'db': const FileIconSpec.asset('assets/icons/database.svg'),
  'sqlite': const FileIconSpec.asset('assets/icons/database.svg'),
  'sqlite3': const FileIconSpec.asset('assets/icons/database.svg'),
  'ipynb': const FileIconSpec.asset('assets/icons/jupyter.svg'),
};

final Map<String, FileIconSpec> _exactMatchIcons = {
  'gradlew': const FileIconSpec(Mdi.console, Color(0xFF26A69A)),
  'gradlew.bat': const FileIconSpec(Mdi.console, Color(0xFF26A69A)),
  'pubspec.yaml': const FileIconSpec.asset('assets/icons/dart.svg'),
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
