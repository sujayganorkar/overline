#!/usr/bin/env bash
# Production script for building Google Play Store Android App Bundle (.aab)
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

# Strip native symbols to optimize download size while preserving debug symbols via NDK debugSymbolLevel
if command -v llvm-strip >/dev/null 2>&1; then
    llvm-strip android/app/src/main/jniLibs/arm64-v8a/libpdfcraft_mobile_api.so || true
    llvm-strip android/app/src/main/jniLibs/x86_64/libpdfcraft_mobile_api.so || true
elif command -v strip >/dev/null 2>&1; then
    strip android/app/src/main/jniLibs/arm64-v8a/libpdfcraft_mobile_api.so || true
    strip android/app/src/main/jniLibs/x86_64/libpdfcraft_mobile_api.so || true
fi

# Build Google Play App Bundle with target ABIs
flutter build appbundle --release --target-platform android-arm64,android-x64

# Validate App Bundle archive integrity and native libraries
python3 - build/app/outputs/bundle/release/app-release.aab <<'PY'
from pathlib import Path
from zipfile import ZipFile
import sys

bundle = Path(sys.argv[1])
required = {
    "base/lib/arm64-v8a/libpdfcraft_mobile_api.so",
    "base/lib/x86_64/libpdfcraft_mobile_api.so",
}
with ZipFile(bundle) as archive:
    entries = set(archive.namelist())
missing = required - entries
if missing:
    raise SystemExit(f"AAB is missing required native libraries: {', '.join(sorted(missing))}")
armv7 = sorted(entry for entry in entries if "armeabi-v7a" in entry)
if armv7:
    raise SystemExit("AAB contains unsupported ARMv7 native libraries: " + ", ".join(armv7))
print("AAB verified: Contains 64-bit PdfCraft native libraries (arm64-v8a & x86_64).")
PY

dist_dir="$ROOT/dist/bundle"
mkdir -p "$dist_dir"

output="$dist_dir/PdfCraft-Mobile-release.aab"
cp build/app/outputs/bundle/release/app-release.aab "$output.tmp"
mv "$output.tmp" "$output"

(
    cd "$dist_dir"
    sha256sum "$(basename "$output")"
) > "$output.sha256.tmp"
mv "$output.sha256.tmp" "$output.sha256"

# Copy Proguard / R8 mapping file if generated
mapping_file="build/app/outputs/mapping/release/mapping.txt"
if [[ -f "$mapping_file" ]]; then
    cp "$mapping_file" "$dist_dir/mapping.txt"
    printf 'ProGuard/R8 obfuscation mapping preserved at: %s/mapping.txt\n' "$dist_dir"
fi

# Copy Native debug symbols zip if generated
symbols_dir="build/app/outputs/native-debug-symbols/release"
if [[ -d "$symbols_dir" ]]; then
    find "$symbols_dir" -name "*.zip" -exec cp {} "$dist_dir/native-debug-symbols.zip" \;
    if [[ -f "$dist_dir/native-debug-symbols.zip" ]]; then
        printf 'Native debug symbols preserved at: %s/native-debug-symbols.zip\n' "$dist_dir"
    fi
fi

short_sha="$(git rev-parse --short=12 HEAD 2>/dev/null || echo "unknown")"
printf 'commit=%s\nbuilt_utc=%s\n' "$short_sha" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$dist_dir/release-info.txt"

printf '\nPlay Store App Bundle (.aab) ready: %s\n' "$output"
ls -lh "$dist_dir"
