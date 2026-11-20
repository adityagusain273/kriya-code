/// Catalog of downloadable local runtimes.
///
/// Each spec maps the runtimeId used by language packs (RunConfig.local.runtimeId)
/// to the Termux packages that make up the runtime. Packages are resolved and
/// downloaded from the Termux apt repository at runtime.
class RuntimeSpec {
  final String runtimeId;
  final String title;
  final String description;
  /// Language packs this runtime makes usable.
  ///
  /// A list because one runtime can serve several languages: the C/C++ toolchain is
  /// the same runtime for both `c` and `cpp`. A single id here could only ever
  /// enable one of them, which is how `bcode.lang.c_cpp` came to refer to a language
  /// pack that does not exist.
  final List<String> extensionIds;
  final List<String> packages;
  final int defaultSizeMb;
  final String approxVersion;

  const RuntimeSpec({
    required this.runtimeId,
    required this.title,
    required this.description,
    required this.extensionIds,
    required this.packages,
    this.defaultSizeMb = 25,
    this.approxVersion = '1.0',
  });
}

const runtimeCatalog = <String, RuntimeSpec>{
  'cpython': RuntimeSpec(
    runtimeId: 'cpython',
    title: 'Python Runtime',
    description: 'Run .py files offline on your device',
    extensionIds: ['bcode.lang.python'],
    packages: ['python', 'libandroid-support', 'ncurses', 'openssl', 'libffi'],
    defaultSizeMb: 10,
    approxVersion: '3.14',
  ),
  'clang': RuntimeSpec(
    runtimeId: 'clang',
    title: 'C / C++ Runtime',
    description: 'Compile and run .c and .cpp files offline',
    extensionIds: ['bcode.lang.c', 'bcode.lang.cpp'],
    packages: ['clang', 'binutils', 'ncurses', 'zlib', 'libc++', 'ndk-sysroot'],
    defaultSizeMb: 52,
    approxVersion: '18',
  ),
  'openjdk': RuntimeSpec(
    runtimeId: 'openjdk',
    title: 'Java Runtime',
    description: 'Run .java files offline on your device',
    extensionIds: ['bcode.lang.java'],
    packages: ['openjdk-17'],
    defaultSizeMb: 38,
    approxVersion: '17',
  ),
  'nodejs': RuntimeSpec(
    runtimeId: 'nodejs',
    title: 'Node.js Runtime',
    description: 'Run JavaScript files offline on your device',
    extensionIds: ['bcode.lang.javascript', 'bcode.lang.typescript'],
    packages: ['nodejs'],
    defaultSizeMb: 32,
    approxVersion: '20',
  ),
  'bash': RuntimeSpec(
    runtimeId: 'bash',
    title: 'Bash Shell',
    description: 'Full bash shell for terminal, npm, pip, git',
    extensionIds: [],
    packages: ['bash', 'coreutils', 'findutils', 'grep', 'sed', 'gawk', 'curl', 'wget', 'git', 'openssh'],
    defaultSizeMb: 12,
    approxVersion: '5.2',
  ),
};

RuntimeSpec? specForRuntime(String runtimeId) => runtimeCatalog[runtimeId];
