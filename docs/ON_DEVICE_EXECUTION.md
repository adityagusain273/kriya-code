# Running code on the user's phone

How B Code executes code on a stock Android phone, and why the build is configured
the way it is. Written to be quotable in a tutorial.

## The obstacle

Android does not let an app run a program it unpacked into its own data directory.
A downloaded interpreter such as CPython ends up at
`/data/user/0/<pkg>/files/runtimes/cpython/bin/python3.14`, which Android labels
`app_data_file`. Executing it fails with `EACCES`:

```
avc: denied { execute } for path=".../runtimes/cpython/bin/python3.14"
     tcontext=u:object_r:app_data_file  scontext=u:r:untrusted_app
```

Moving the program does not help. `/storage/emulated` — the shared volume every
other app can see — is mounted **`noexec`**, so a program there cannot be started
either. That is why the obvious approaches (unpack and run, or run from `/sdcard`)
both dead-end.

## The fix: start programs through the system dynamic linker

The policy refuses *executing* an app-owned file. It does not forbid *mapping* one.
`/system/bin/linker64` is a system file the app is allowed to execute, and the
program handed to it is only mapped into the process — which is permitted. So:

```
execve("/system/bin/linker64", ["/system/bin/linker64", "<program>", "<args...>"])
```

runs the program. `LD_LIBRARY_PATH` is still honoured, so the runtime finds its
own `libpython`, `libexpat`, `libc++_shared` and friends inside the app's private
prefix.

`ExecPlugin.launchArgv()` does this for every program that is not part of the OS
image. It also routes non-ELF `#!` scripts to `/system/bin/sh`, since the kernel
would otherwise have to execute the script file itself.

This is the same mechanism Acode uses in its Play build, which targets SDK 36 and
still runs a complete Linux userland.

Because of this, **the app can keep a modern `targetSdk`**, which is what makes it
distributable through stores that pay per download. There is no trade-off between
"runs code" and "passes store review".

### Verified on device

| Check | Result |
|---|---|
| Direct `execve` of an app-owned ELF | `Permission denied` |
| `linker64 <ELF>` | exit 0, program output correct |
| `linker64 <ELF>` with `LD_LIBRARY_PATH` to a private lib dir | exit 0, library resolved |
| Same, through `ExecPlugin` (full path incl. sandbox checks) | exit 0 |

Reproduce it yourself:

```bash
flutter build apk --debug \
  --dart-define=BCODE_EXEC_SELFTEST=true \
  --dart-define=BCODE_PROBE_DIR=/data/data/com.bcode.editor/files
adb logcat | grep BCODE_EXEC_SELFTEST
```

### The other route, and why it is not the default

Apps that target **SDK 28 or lower** are placed in the legacy `untrusted_app_28`
SELinux domain, which *is* allowed to execute app-owned files, so no linker
indirection is needed. This is why Termux works, and why Acode publishes a
`targetSdk 28` F-Droid build.

B Code does not use it by default: stores that pay per download require a recent
`targetSdk`, and a build that cannot be listed in them earns nothing. The route
remains available with `-Pbcode.targetSdk=28` for local sideloading.

## The shared workspace

Termux runs as a different Linux user and cannot read B Code's private directory.
A SAF `content://` URI does not help either, because URI grants are per-app, so
Termux can never open a URI granted to B Code. The only thing both apps can see is
a plain path on the shared volume, `/storage/emulated/0/BCode`.

That requires All-files access, which is a broad grant a store scrutinises, so it
is **opt-in and off by default**:

* A fresh install asks for nothing at all. The workspace is an app-private folder,
  which is enough to edit, run, and use Git.
* *Settings → Share folder with other apps* sends the user to the system screen for
  All-files access. The preference is only stored if such a screen exists, so the
  switch never promises something the device cannot deliver.
* Until the grant is given, the app keeps using the private folder and the settings
  entry says it is waiting for permission. Losing or revoking the grant costs the
  user nothing but the sharing.
* On some OEM builds (ColorOS, for one) that system screen is itself behind the
  device password. That is the ROM's choice and cannot be bypassed.

With the grant in place the workspace moves on the next app start, and Termux needs
its own All-files grant to read the same files.

## Runtimes are installed, not shipped

Runtimes are **not** bundled by default. They are resolved, downloaded, verified
and unpacked on demand, the way VS Code installs an extension. That is a deliberate
trade, because bundling is wrong on both axes that matter:

| | Bundled | Installed on demand |
|---|---|---|
| APK size | +9.5 MB Python, +23 MB Node, **+101 MB** OpenJDK, per ABI | unchanged |
| New language version | needs an app release | reaches the user immediately |
| User's data | none | one download per language they pick |
| Works offline | yes | only what is already installed |

Bundling every language would mean roughly 134 MB of payload *per ABI*, so about
400 MB across arm64, armeabi-v7a and x86_64, before the Flutter engine. That is past
Google Play's 200 MB APK ceiling and a punishing install on a cheap phone. Worse, a
bundled runtime is frozen: when Python 3.15 ships, users would need a new APK. With
downloads they simply get it.

The downloads screen shows the version, the size and the package count *before* a
download starts, so the choice is informed:

```
Python Runtime     v3.14.6-1  ·  9.5 MB  ·  17 packages
Java Runtime       v17.0.20   · 101.3 MB ·  36 packages
```

### Integrity

Every package is SHA-256 verified against the repository index before it is
unpacked and marked executable. A `.deb` that reaches the extractor becomes a
program the app runs as its own UID, so an unverifiable package is refused outright
rather than trusted. Archives are also checked for absolute paths, `..` traversal,
escaping symlinks, entry count and total size.

### Offline-first builds

Bundling remains available as a build-time choice, not a product decision. Running

```bash
python3 tool/bundle_runtime.py cpython --arch aarch64
```

resolves the same dependency closure, verifies the same checksums, and writes the
tree to `android/app/src/main/assets/bundled_runtime/<arch>/<id>/` in exactly the
layout the downloader produces. At first launch `ExecPlugin.installBundledRuntime`
unpacks it into the same location a download would use, and the runtime's language
pack is enabled with it, so the app works with no network at all. The downloads
screen labels such a runtime **Bundled** instead of **Installed**.

The payload is git-ignored: it is a large build input, not source.

## Diagnosing a failure

`ExecPlugin` turns a platform refusal into an explanation instead of a raw
`EACCES`:

* **shared storage** — the program is on the `noexec` volume; build the output
  into app storage.
* **system linker cannot load this kind of binary** — a static or non-PIE
  executable; the linker only loads `ET_DYN` images.