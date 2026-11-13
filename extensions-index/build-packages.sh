#!/usr/bin/env bash
# Builds extensions-index/packages/*.bcext from extensions-index/src/*.
#
# Run after editing a manifest: the published index points at the .bcext files,
# not at the source folders.
set -euo pipefail

cd "$(dirname "$0")"
mkdir -p packages

for src in src/*/; do
  [ -f "$src/extension.json" ] || continue
  read -r id version < <(python3 - "$src/extension.json" <<'PY'
import json, re, sys
with open(sys.argv[1], encoding="utf-8") as handle:
    manifest = json.load(handle)
identifier = str(manifest.get("id", ""))
if not re.fullmatch(r"[a-z0-9][a-z0-9._-]{2,79}", identifier):
    sys.exit(f"Invalid extension id: {identifier!r}")
print(identifier, manifest.get("version", "1.0.0"))
PY
)
  out="packages/$id-$version.bcext"
  out="$(pwd)/$out"
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
done