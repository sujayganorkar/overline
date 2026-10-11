# PdfCraft Mobile

Flutter UI over the [PdfCraft](https://github.com/storytold/pdfcraft) Rust engine, bridged with
[flutter_rust_bridge](https://github.com/fzyzcjy/flutter_rust_bridge). Offline-first; Android first,
iOS next (shared Rust/Flutter code).

## Phase 1 status — working PDF viewer

Verified on this machine (Linux, NDK r27c, Flutter 3.47.7):

| Claim | Status | Evidence |
|---|---|---|
| Engine crates isolated from the egui desktop UI | done | Adapter path-deps only `pdfcraft-engine` + `pdfcraft-render` + vendored patches; no `ui-egui`/`rfd`/`eframe` in the graph |
| Engine work through the bridge | host verified | Rust integration test opens an engine-generated PDF, reads page count/size, renders 816×1056 PNG at 96 dpi, saves/reopens, rejects malformed input, and closes handles |
| Android ARM64 + x86_64 native libraries and APK packaging | done | Build explicitly targets only ABIs with a PdfCraft library; debug/release APKs contain both |
| Android app runtime (open/render/navigate/Save As/reopen) | verified | Android 15/API 35 x86_64 emulator; user reports success on Galaxy S26 Ultra (India) |

The app UI: open PDF (system document picker), page count, page render at 96 dpi (pinch-zoom), page
navigation, password prompt, and Save As through the system document provider. The flow passed on
the Android emulator and was user-confirmed on a Galaxy S26 Ultra. The phone's Android version and
logs were not captured in the engineering session.

## Layout

```
Cargo.toml            workspace; relative engine deps + vendored hayro/lopdf patches
third_party/pdfcraft  pinned upstream Git submodule; see .gitmodules and plan/decisions/
rust/                 the bridge crate (adapter, no PDF logic of its own)
  src/api.rs          Flutter-facing API; engine Session lives on a worker thread
  tests/smoke.rs      host end-to-end test of the bridge
  examples/make_pdf.rs  generates a test PDF with the engine
lib/                  Flutter app (lib/bridge is FRB-generated — do not edit)
tools/env.sh          toolchain env (source before builds)
~/sdks/                optional local Flutter/Android SDK installs (not required paths in Cargo)
```

## Why the engine lives outside this repo

`third_party/pdfcraft` is a submodule pinned to an upstream commit. The Cargo workspace excludes its
nested workspace, references engine crates via relative paths, and patches crates.io to upstream's
vendored `hayro`/`lopdf` sources. This preserves the engine's required patches and avoids dependence
on a developer-specific absolute filesystem path. See `plan/decisions/0001-pdfcraft-pinning.md`.

## Build & run

See `SETUP.md` for the one-time toolchain setup. Short version:

```bash
source tools/env.sh
cargo test -p pdfcraft-mobile-api                              # engine round-trip on host
flutter_rust_bridge_codegen generate --rust-root rust --rust-input crate::api --dart-output lib/bridge   # after API changes
cargo ndk -t arm64-v8a -t x86_64 build --release -p pdfcraft-mobile-api
cp target/aarch64-linux-android/release/libpdfcraft_mobile_api.so android/app/src/main/jniLibs/arm64-v8a/
cp target/x86_64-linux-android/release/libpdfcraft_mobile_api.so android/app/src/main/jniLibs/x86_64/
flutter run --release --target-platform android-arm64,android-x64 # with a device attached
```

For a fresh clone, initialize the pinned engine first: `git submodule update --init --recursive`.
Keep both `Cargo.lock` and `pubspec.lock`; these are application lockfiles.

## APK on every push

The local pre-push hook builds a release APK at `dist/apk/PdfCraft-Mobile-latest.apk` and blocks a
push if the working tree is dirty or the pushed commit is not `HEAD`. To enable it on a fresh clone:

```bash
git config --local core.hooksPath .githooks
```

GitHub Actions also runs the checks and builds an APK for each push. Download it from **Actions →
Android APK → latest successful run → Artifacts** (`PdfCraft-Mobile-<commit SHA>`). Artifacts are
retained for 30 days. The APK targets Android ARM64 and x86_64 only, matching the packaged Rust
libraries. It is a debug-signed test build, not a store-release package. To build manually without
pushing, run `source tools/env.sh && tools/build-apk.sh`.

## Product MVP direction

The first product MVP is the full manual PDF editor scope: reading/search, annotations and text
tools, pages/documents, forms/signatures, OCR/conversion/compression, and reliable save/undo/recovery.
The agent/chat/model experience comes later. Build a typed operation layer for manual controls now
so future agents can call the same validated operations. Audit each desired capability against the
real PdfCraft API and test it on mobile before claiming support. See [`plan/`](plan/README.md) for
the decision, staged roadmap, and current status.
