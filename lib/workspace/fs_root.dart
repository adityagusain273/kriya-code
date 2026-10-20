/// The absolute workspace root the editor is currently pointed at.
///
/// Lives here rather than in `main.dart` so UI code can read it without
/// importing the entrypoint, which would create an import cycle.
class FsRoot {
  final String path;
  const FsRoot(this.path);
}
