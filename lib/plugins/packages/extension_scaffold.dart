import 'dart:convert';

import '../../workspace/fs_service.dart';

/// Writes a working example extension into the workspace.
///
/// The developer edits it in B Code itself, installs it with "Load unpacked",
/// then shares the folder (or a `.bcext` built from it) when it is ready.
class ExtensionScaffold {
  static const folder = 'extensions';

  static Future<String> create(FsService fs) async {
    var name = 'hello-bcode';
    var suffix = 2;
    while (fs.exists('$folder/$name')) {
      name = 'hello-bcode-$suffix';
      suffix++;
    }

    final root = '$folder/$name';
    await fs.writeFile('$root/extension.json', _manifestFor(name));
    await fs.writeFile('$root/README.md', _readme);
    return root;
  }

  static String _manifestFor(String name) =>
      const JsonEncoder.withIndent('  ').convert({
        'manifestVersion': 1,
        'id': 'com.example.$name',
        'name': 'Hello B Code',
        'version': '1.0.0',
        'description': 'Example extension: INI highlighting and a snippet.',
        'author': 'Your name',
        'license': 'MIT',
        'contributes': {
          'languages': [
            {
              'id': 'ini-example',
              'name': 'INI (example)',
              'extensions': ['ini'],
              'grammar': 'ini',
              'indentWidth': 2,
              'blockOpeners': ['[', '{'],
              'blockClosers': [']', '}'],
            }
          ],
          'snippets': {
            'ini-example': {
              'hello': {
                'label': 'Hello comment',
                'body': ['; hello from B Code'],
              }
            }
          },
        },
      });

  static const _readme = '''
# Hello B Code extension

This folder is a working example. Edit `extension.json`, then open
Extensions -> Load unpacked in B Code to install this exact folder.

Before publishing, change `id` to something unique such as
`com.yourname.mylanguage`, and change `name`, `author` and `description`.

What you can contribute:

- `languages` - highlighting for new file types. `grammar` is a highlight.js
  grammar name such as rust, go, kotlin, swift, ruby, php, sql or yaml.
- `snippets` - trigger text per language.
- `themes` - editor colour schemes.

B Code extensions are declarative: they contain no executable code, so
installing one cannot run anything on the device.

Publishing:

1. Zip the contents of this folder, not the folder itself, as
   `my-extension.bcext` (or run `tool/package-extension.sh .` on a computer).
2. Host it anywhere HTTPS, for example a GitHub Release asset.
3. Public: list it in an index JSON and tell users to add that index URL.
   Private: share the file or an unlisted URL directly.

Docs: docs/EXTENSIONS.md
''';
}
