# PdfCraft Mobile

Flutter UI over the [PdfCraft](https://github.com/storytold/pdfcraft) Rust engine, bridged with
[flutter_rust_bridge](https://github.com/fzyzcjy/flutter_rust_bridge). Offline-first; Android first,
iOS next (shared Rust/Flutter code).

## Phase 1 status — working PDF viewer

Verified on this machine (Linux, NDK r27c, Flutter 3.47.7):

| Claim | Status | Evidence |
|---|---|---|
| Engine crates isolated from the egui desktop UI | done | Adapter path-deps only `pdfcraft-engine` + `pdfcraft-render` + vendored patches; no `ui-egui`/`rfd`/`eframe` in the graph |
| Engine compiles for Android ARM64 + x86_64 | done | `target/{aarch64,x86_64}-linux-android/release/libpdfcraft_mobile_api.so` (NDK r27c ELF, API 21+) |
| Engine work through the bridge | done | `cargo test -p pdfcraft-mobile-api` — opens an engine-generated PDF, page count/size, renders a 816x1056 PNG at 96 dpi, saves and re-opens the file |
| APK bundles the engine | done | `build/app/outputs/flutter-apk/app-debug.apk` contains `lib/*/libpdfcraft_mobile_api.so` for arm64-v8a and x86_64 |
| On-device run (open + render in the UI) | **pending** | Needs a phone or emulator; `flutter run --release` with a device connected |

The app UI: open PDF (file picker), page count, page size, page render at 96 dpi (pinch-zoom),
page navigation, and "Save" (engine incremental save) to the app documents dir.

## Layout

```
Cargo.toml            workspace; pins PdfCraft engine path deps + vendored hayro/lopdf patches
rust/                 the bridge crate (adapter, no PDF logic of its own)
  src/api.rs          Flutter-facing API; engine Session lives on a worker thread
  tests/smoke.rs      host end-to-end test of the bridge
  examples/make_pdf.rs  generates a test PDF with the engine
lib/                  Flutter app (lib/bridge is FRB-generated — do not edit)
tools/env.sh          toolchain env (source before builds)
~sdks/                flutter, android-sdk (NDK 27.2), user-space installs
~/src/pdfcraft        the engine fork (origin = storytold/pdfcraft; our branches, if any)
```

## Why the engine lives outside this repo

`~/src/pdfcraft` is a fork clone (`origin` tracks upstream). Our workspace references its engine
crates by path and patches crates.io with its `vendor/` copies, because the engine currently
depends on patched `hayro`/`lopdf` that are not yet on crates.io. Keeping the engine in its own
repo makes upstream syncs `git fetch && git rebase origin/main`.

## Build & run

See `SETUP.md` for the one-time toolchain setup. Short version:

```bash
source tools/env.sh
cargo test -p pdfcraft-mobile-api                              # engine round-trip on host
flutter_rust_bridge_codegen generate --rust-root rust --rust-input crate::api --dart-output lib/bridge   # after API changes
cargo ndk -t arm64-v8a -t x86_64 build --release -p pdfcraft-mobile-api
cp target/aarch64-linux-android/release/libpdfcraft_mobile_api.so android/app/src/main/jniLibs/arm64-v8a/
cp target/x86_64-linux-android/release/libpdfcraft_mobile_api.so android/app/src/main/jniLibs/x86_64/
flutter run --release                                          # with a device attached
```

## Next (Phase 2)

Editing, annotations, forms, signatures — all already exposed by `pdfcraft-engine` (`Session::apply`
with `Edit` variants, undo/redo, form fields). The bridge's `Engine` handle is the integration point.
