#!/usr/bin/env bash
# Build a .bcext package from an extension folder.
#
#   tool/package-extension.sh path/to/my-extension [output.bcext]
#
# The archive contains extension.json at its root, which is what B Code
# expects when installing from file or URL.
set -euo pipefail

src="${1:-.}"
if [ ! -f "$src/extension.json" ]; then
  echo "No extension.json in $src" >&2
  exit 1
fi

read -r id version < <(python3 - "$src/extension.json" <<'PY'
import json, re, sys
try:
    with open(sys.argv[1], encoding="utf-8") as handle:
        manifest = json.load(handle)
except Exception as error:
    sys.exit(f"Cannot read extension.json: {error}")
identifier = str(manifest.get("id", ""))
if not re.fullmatch(r"[a-z0-9][a-z0-9._-]{2,79}", identifier):
    sys.exit(f"Invalid extension id: {identifier!r}")
print(identifier, manifest.get("version", "1.0.0"))
PY
)

out="${2:-$PWD/$id-$version.bcext}"
mkdir -p "$(dirname "$out")"
out="$(cd "$(dirname "$out")" && pwd)/$(basename "$out")"
rm -f "$out"

if command -v zip >/dev/null 2>&1; then
  (cd "$src" && zip -qr "$out" . -x '*.bcext' -x '.git/*')
else
  python3 - "$src" "$out" <<'PY'
import os, sys, zipfile
source, target = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED) as archive:
    for root, dirs, files in os.walk(source):
        dirs[:] = [d for d in dirs if d != ".git"]
        for name in files:
            if name.endswith(".bcext"):
                continue
            path = os.path.join(root, name)
            archive.write(path, os.path.relpath(path, source))
PY
fi

echo "Wrote $out"
echo "Next: upload it over HTTPS, then share the link or list it in an index."
