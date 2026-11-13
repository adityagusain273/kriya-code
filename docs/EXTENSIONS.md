# B Code extensions

B Code has two extension layers:

1. **Installable packages** — `.bcext` files that anyone can create, share and
   install from the Extensions page. They add languages, snippets and syntax
   themes. This is the layer described below.
2. **Bundled language packs** — Dart classes compiled into the app. They add
   highlighting *and* run support for languages whose runtimes ship with B Code.
   See [Bundled language packs](#bundled-language-packs).

A package is **data, not code**. Installing one cannot execute anything on the
device: B Code only reads `extension.json` and registers the declared
contributions. That is why packages are safe to install from a URL without a
code-signing or review pipeline, and why they cannot change the UI or access
your files.

## Package layout

```
my-extension/
├── extension.json      required, at the archive root
├── README.md           optional, for humans
└── snippets/…          optional, not read yet
```

Build the archive with the contents at the root, **not** the folder itself:

```bash
tool/package-extension.sh path/to/my-extension
# writes my-extension-1.0.0.bcext
```

The installer also accepts a zip wrapped in one top-level folder, but the root
form is the one to publish.

## `extension.json`

```json
{
  "manifestVersion": 1,
  "id": "com.example.rust",
  "name": "Rust",
  "version": "1.0.0",
  "description": "Rust highlighting, snippets and a dark theme.",
  "author": "Your Name",
  "license": "MIT",
  "homepage": "https://github.com/you/bcode-rust",
  "contributes": {
    "languages": [
      {
        "id": "rust",
        "name": "Rust",
        "extensions": ["rs"],
        "grammar": "rust",
        "indentWidth": 4,
        "insertSpaces": true,
        "blockOpeners": ["{"],
        "blockClosers": ["}"]
      }
    ],
    "snippets": {
      "rust": {
        "fn": {
          "label": "Function",
          "body": ["fn name() {", "\t$0", "}"]
        }
      }
    },
    "themes": [
      {
        "id": "my-rust-dark",
        "name": "My Rust Dark",
        "colors": {
          "background": "#101010",
          "foreground": "#eeeeee",
          "keyword": "#ff7b72",
          "string": "#a5d6ff",
          "comment": "#8b949e"
        }
      }
    ]
  }
}
```

### Top-level fields

| Field | Required | Notes |
|---|---|---|
| `manifestVersion` | yes | Must be `1`. |
| `id` | yes | 3–80 characters: lowercase letters, digits, `.`, `_`, `-`. Must be unique. `bcode.` is reserved for bundled extensions. |
| `name` | yes | Shown in the Extensions page. |
| `version` | no | Defaults to `1.0.0`. Informational only; reinstalling replaces the old copy. |
| `description`, `author`, `license`, `homepage` | no | Shown in the Extensions page. |

### `contributes.languages`

Up to 20 entries. Each language adds highlighting for its file extensions.

| Field | Required | Notes |
|---|---|---|
| `id` | yes | Lowercase letters, digits, `_`, `+`, `-`. Must not collide with a bundled language (`python`, `java`, `c`, `cpp`, `javascript`, `typescript`, `html`, `css`, `json`, `markdown`). |
| `name` | yes | Human-readable name. |
| `extensions` | yes | 1–20 file extensions without the dot. Must not collide with a bundled extension (`.py`, `.js`, `.ts`, `.html`, `.css`, `.json`, `.md`, `.c`, `.h`, `.cpp`, …). |
| `grammar` | yes | A highlight.js grammar name. Must exist in the [highlight package](https://pub.dev/packages/highlight): `rust`, `go`, `kotlin`, `swift`, `ruby`, `php`, `sql`, `yaml`, `dockerfile`, `makefile`, and about 180 more. |
| `indentWidth` | no | 1–8, default 4. |
| `insertSpaces` | no | Default `true`. |
| `blockOpeners` / `blockClosers` | no | Strings that open/close an indented block, used by auto-indent. |

A file is highlighted by its extension, so `Dockerfile` (no extension) cannot
be matched yet. Use `dockerfile` as an extension only if your files are named
`*.dockerfile`.

### `contributes.snippets`

Keyed by language id, then by trigger. The trigger is what the user types in
the snippet list; `body` is a string or a list of lines.

```json
"snippets": {
  "python": {
    "main": {
      "label": "Main guard",
      "description": "if __name__ == '__main__'",
      "body": ["if __name__ == \"__main__\":", "\tmain()"]
    }
  }
}
```

Snippets can target bundled languages (`python`, `javascript`, …) or languages
from the same package. Limit: 500 snippets per package, 4000 characters each.

### `contributes.themes`

Up to 10 themes. `colors` uses highlight.js token classes plus `background` and
`foreground`:

```json
{
  "id": "my-rust-dark",
  "name": "My Rust Dark",
  "colors": {
    "background": "#101010",
    "foreground": "#eeeeee",
    "keyword": "#ff7b72",
    "string": "#a5d6ff",
    "comment": "#8b949e",
    "number": "#79c0ff",
    "built_in": "#ffa657",
    "type": "#ffa657",
    "function": "#d2a8ff"
  }
}
```

Colours accept `#RGB`, `#RRGGBB` or `#AARRGGBB`. External themes appear in
**Settings → Appearance → Syntax Theme** and are namespaced internally as
`ext.<extension id>.<theme id>` so two packages cannot replace each other's
themes or a bundled one.

## Creating an extension

### On the phone

1. Open **Extensions** → overflow menu → **Create extension**.
2. B Code writes `extensions/hello-bcode/` in your workspace with a working
   example.
3. Edit `extension.json` in the editor.
4. **Extensions** → overflow menu → **Load unpacked**, pick the folder.
5. Reopen an edited file to apply new highlighting. Snippets and themes apply
   immediately.
6. **Extensions** → **Export .bcext** builds the shareable package through the
   system file picker.

Reinstall after every edit; "Load unpacked" copies the folder into app-private
storage, so the workspace copy stays yours to edit.

### On a computer

```bash
mkdir my-extension && cd my-extension
$EDITOR extension.json
tool/package-extension.sh .
# share the .bcext, or upload it to an HTTPS URL
```

There is no B Code account and no server. An extension is "public" when it is
listed in an index that users can add, and "private" when it is only shared by
file or by an unlisted URL.

## Installing

| Source | Where |
|---|---|
| File on the device | Extensions → **Install from file** (a `.bcext` or `.zip`) |
| HTTPS URL | Extensions → **Install from URL** |
| A folder in the workspace | Extensions → **Load unpacked** |
| A public index | Extensions → **Sources → Add source** |

The official index ships as a default source, so a fresh install already has
the published packages. It is an ordinary source: remove it under Sources and
it stays removed.

Packages live in app-private storage (`<app support>/extensions/<id>`). Removing
an extension deletes the package and unloads its languages, snippets and themes
in the same session; it does not touch your workspace.

When a source lists a newer `version` than the installed copy, its card changes
from **Get** to **Update**. Installing an update replaces the package in place.

## Publishing: public and private

### Private / unlisted

Upload the `.bcext` anywhere HTTPS and share the link directly. Only people
with the link can install it. B Code does not support authenticated downloads,
so a link that requires a login will not install.

### Public: host an index

An index is a JSON file listing packages. Host it on GitHub Pages, raw
`githubusercontent.com`, a company server, or any static host. Add its URL in
**Extensions → Sources**.

```json
{
  "extensions": [
    {
      "id": "com.example.rust",
      "name": "Rust",
      "version": "1.0.0",
      "description": "Rust highlighting and snippets.",
      "author": "Your Name",
      "download": "https://github.com/you/bcode-rust/releases/download/v1.0.0/rust-1.0.0.bcext",
      "homepage": "https://github.com/you/bcode-rust"
    }
  ]
}
```

- `download` may be absolute or relative to the index URL.
- Entries without an `https` download are ignored.
- Duplicate ids across sources: the first source wins.
- The same index can list many packages. A source is trusted only for
  discovery: the installed package's own manifest is validated again.

A zero-cost public workflow:

1. Create `github.com/you/bcode-extensions`.
2. Put `extension.json` and sources in folders, and publish a `.bcext` as a
   GitHub Release asset.
3. Add an `index.json` to the repo and enable GitHub Pages (or use the raw URL).
4. Users add `https://you.github.io/bcode-extensions/index.json` as a source.

The official index is maintained in this repository at `extensions-index/` and
published to the public `adityagusain273/b-code` repository, which is what the
default source URL serves. Edit a manifest under
`extensions-index/src/<name>/`, run `extensions-index/build-packages.sh` to
rebuild the `.bcext`, then copy the folder to the public repo and push it to
`main`. Keep the two in step: the app reads the public copy.

## Limits and validation

| Limit | Value |
|---|---|
| Package size | 16 MB compressed, 48 MB unpacked |
| Entries | 2,000 |
| `extension.json` | 256 KB |
| Languages | 20 per package |
| Snippets | 500 per package, 4,000 characters each |
| Themes | 10 per package, 200 colours each |

The installer rejects path traversal, symlinks, absolute paths and duplicate
entries. A package that fails validation is not installed. Malformed installed
packages are skipped at startup instead of blocking the app.

Bundled languages and extensions always win. A package cannot replace `python`
or claim `.py`; it is rejected at install time and skipped again at load time.

## Bundled language packs

Languages that also need to **run** (`python`, `java`, `c`, `cpp`, `javascript`)
are Dart classes in `lib/plugins/builtin/`. They implement `BCodeExtension`,
register a `LanguageContribution` with highlighting and a `RunConfig`, and are
listed in `lib/plugins/builtin/builtin_extensions.dart`.

This layer is compiled into the app because Dart AOT cannot load new Dart code
at runtime, and because a runtime needs a native binary that the app knows how
to launch. A third-party language with run support needs either a bundled
runtime in `lib/execution/runtime_catalog.dart` or a future JavaScript extension
host.

## What packages cannot do (yet)

- Run code or access the network.
- Add editor commands, toolbar buttons or custom UI.
- Add file-creation templates.
- Provide a language server or debugger.
- Execute a new runtime that the app does not already bundle.

The next step for this layer is a sandboxed JavaScript host for commands and UI,
reusing the same manifest. It is deliberately not shipped until it can run with
a real permission model; the current system's safety comes from having no code
execution at all.

## Troubleshooting

- **"Unknown grammar"** — check the name against the highlight package's
  `languages/` directory; use the file name without `.dart`.
- **"already claimed by a bundled language"** — pick a different extension, or
  add highlighting for a language the app does not already have.
- **Installed but no highlighting** — open a file that matches one of the
  package's extensions. An already-open tab keeps the grammar it was opened
  with.
- **Removed but still active** — removal is immediate. Open tabs lose the
  grammar and fall back to plain text; if a tab still shows colours, close and
  reopen it.
