#!/usr/bin/env bash
# Works around google_mobile_ads 5.3.1 failing to configure on Gradle 9:
#
#   google_mobile_ads-5.3.1/android/build.gradle:58
#   > Could not get unknown property 'all' for configuration container
#
# The plugin's afterEvaluate block iterates `configurations` with a Groovy
# for-in. Upstream fixed this in google_mobile_ads 7.0.0 (issue 1361); this
# app is pinned to 5.3.1 because a four-major upgrade changes the ads SDK.
#
# The block only adds legacy `android.arch.lifecycle` compileOnly
# dependencies when the Flutter embedding is absent, which never applies to a
# Flutter app, so it is removed before Gradle configures the plugin.
#
# Idempotent, and a no-op when the plugin is absent or already fixed. Safe to
# run before any Gradle invocation.
set -euo pipefail

cache="${PUB_CACHE:-$HOME/.pub-cache}"
files="$(find "$cache/hosted" -path '*/google_mobile_ads-*/android/build.gradle' 2>/dev/null || true)"

if [ -z "$files" ]; then
    echo "google_mobile_ads not found under $cache/hosted; nothing to do"
    exit 0
fi

patched=0
while IFS= read -r build_gradle; do
    grep -q 'for (def configuration : configurations)' "$build_gradle" || continue

    python3 - "$build_gradle" <<'PY'
import sys

path = sys.argv[1]
lines = open(path).read().splitlines(keepends=True)

try:
    start = next(i for i, line in enumerate(lines)
                 if line.startswith('afterEvaluate {'))
except StopIteration:
    print(f'no afterEvaluate block in {path}')
    raise SystemExit(0)

depth = 0
end = len(lines) - 1
for i in range(start, len(lines)):
    depth += lines[i].count('{') - lines[i].count('}')
    if i > start and depth == 0:
        end = i
        break

open(path, 'w').write(''.join(lines[:start] + lines[end + 1:]))
print(f'patched {path}')
PY
    patched=1
done <<< "$files"

if [ "$patched" -eq 0 ]; then
    echo "google_mobile_ads already patched; nothing to do"
fi