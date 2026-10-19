#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tools/env.sh"
cd "$ROOT"

for command in cargo flutter; do
    if ! command -v "$command" >/dev/null 2>&1; then
        printf 'Required command not found: %s\n' "$command" >&2
        exit 1
    fi
done

flutter pub get --enforce-lockfile
cargo ndk -t arm64-v8a -t x86_64 build --release --locked -p pdfcraft-mobile-api

mkdir -p android/app/src/main/jniLibs/arm64-v8a android/app/src/main/jniLibs/x86_64
cp target/aarch64-linux-android/release/libpdfcraft_mobile_api.so android/app/src/main/jniLibs/arm64-v8a/
cp target/x86_64-linux-android/release/libpdfcraft_mobile_api.so android/app/src/main/jniLibs/x86_64/

flutter build apk --release --target-platform android-arm64,android-x64

python3 - build/app/outputs/flutter-apk/app-release.apk <<'PY'
from pathlib import Path
from zipfile import ZipFile
import sys

apk = Path(sys.argv[1])
required = {
    "lib/arm64-v8a/libpdfcraft_mobile_api.so",
    "lib/x86_64/libpdfcraft_mobile_api.so",
}
with ZipFile(apk) as archive:
    entries = set(archive.namelist())
missing = required - entries
if missing:
    raise SystemExit(f"APK is missing Rust libraries: {', '.join(sorted(missing))}")
armv7 = sorted(entry for entry in entries if entry.startswith("lib/armeabi-v7a/"))
if armv7:
    raise SystemExit("APK contains unsupported ARMv7 native libraries: " + ", ".join(armv7))
print("APK contains Overline native libraries for ARM64 and x86_64 only.")
PY

short_sha="$(git rev-parse --short=12 HEAD)"
worktree_state=clean
if [[ -n "$(git status --porcelain --untracked-files=normal)" ]]; then
    worktree_state=dirty
fi
output="$ROOT/dist/apk/Overline-latest.apk"
mkdir -p "$(dirname "$output")"
cp build/app/outputs/flutter-apk/app-release.apk "$output.tmp"
mv "$output.tmp" "$output"
(
    cd "$(dirname "$output")"
    sha256sum "$(basename "$output")"
) > "$output.sha256.tmp"
mv "$output.sha256.tmp" "$output.sha256"
printf 'commit=%s\nworktree=%s\nbuilt_utc=%s\n' \
    "$short_sha" "$worktree_state" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$output.txt.tmp"
mv "$output.txt.tmp" "$output.txt"

printf '\nAPK ready: %s\nCommit: %s (%s worktree)\n' "$output" "$short_sha" "$worktree_state"
