/// Catalog of downloadable local runtimes.
///
/// Each spec maps the runtimeId used by language packs (RunConfig.local.runtimeId)
/// to the Termux packages that make up the runtime. Packages are resolved and
/// downloaded from the Termux apt repository at runtime.
class RuntimeSpec {
  final String runtimeId;
  final String title;
  final String description;
  final String extensionId;
  final List<String> packages;

  const RuntimeSpec({
    required this.runtimeId,
    required this.title,
    required this.description,
    required this.extensionId,
    required this.packages,
  });
}

const runtimeCatalog = <String, RuntimeSpec>{
  'cpython': RuntimeSpec(
    runtimeId: 'cpython',
    title: 'Python Runtime',
    description: 'Run .py files offline on your device',
    extensionId: 'bcode.lang.python',
    packages: ['python', 'libandroid-support', 'ncurses', 'openssl', 'libffi'],
  ),
  'clang': RuntimeSpec(
    runtimeId: 'clang',
    title: 'C / C++ Runtime',
    description: 'Compile and run .c and .cpp files offline',
    extensionId: 'bcode.lang.c_cpp',
    packages: ['clang', 'binutils', 'ncurses', 'zlib', 'libc++'],
  ),
  'openjdk': RuntimeSpec(
    runtimeId: 'openjdk',
    title: 'Java Runtime',
    description: 'Run .java files offline on your device',
    extensionId: 'bcode.lang.java',
    packages: ['openjdk-17'],
  ),
  'nodejs': RuntimeSpec(
    runtimeId: 'nodejs',
    title: 'Node.js Runtime',
    description: 'Run JavaScript files offline on your device',
    extensionId: 'bcode.lang.javascript',
    packages: ['nodejs'],
  ),
  'bash': RuntimeSpec(
    runtimeId: 'bash',
    title: 'Bash Shell',
    description: 'Full bash shell for terminal, npm, pip, git',
    extensionId: 'bcode.termux',
    packages: ['bash', 'coreutils', 'findutils', 'grep', 'sed', 'gawk', 'curl', 'wget', 'git', 'openssh'],
  ),
};

RuntimeSpec? specForRuntime(String runtimeId) => runtimeCatalog[runtimeId];
