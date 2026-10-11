# Project status

**Updated:** 2026-10-12  
**Current milestone:** M1 — Android PDF viewer vertical slice (emulator and physical phone verified)  
**Next acceptance:** continue M2 file-safety/lifecycle checks, then validate iOS on macOS/Xcode.

**Product scope decision:** the first product MVP covers the complete agreed manual PDF editing
scope. Agent UI, model runtimes, and cloud execution are later; the typed operation foundation is
designed during manual feature development so both paths share deterministic handlers.

## Verified in the current working tree

- `cargo test -p pdfcraft-mobile-api`: integration smoke test passed on Linux using PdfCraft's own
  `Session::create_from_text`. It opens, checks page count/size, renders a 816×1056 PNG at 96 DPI,
  rejects bad pages/DPI and malformed bytes, saves/reopens, and closes all documents.
- `cargo clippy -p pdfcraft-mobile-api --all-targets -- -D warnings`: passed.
- `flutter analyze` and `flutter test`: passed; tests cover document page-heading singular/plural
  and viewer engine-initialization success/failure through an injected bridge interface.
- `flutter_rust_bridge_codegen generate --rust-root rust --rust-input crate::api --dart-output lib/bridge`:
  completed with FRB 2.13.0.
- `cargo ndk -t arm64-v8a -t x86_64 build --release -p pdfcraft-mobile-api`: both Android target
  builds passed from the relative-path pinned submodule workspace.
- `flutter build apk --debug`: passed. APK inspection found `libpdfcraft_mobile_api.so` under
  `lib/arm64-v8a/` and `lib/x86_64/`.
- Installed and launched the APK on the `pdfcraft` x86_64 AVD (Android 15 / API 35). FRB initialized
  and the Rust worker started; the viewer opened a 2-page PDF produced by PdfCraft and showed the
  actual rendered page image. Tapping Next changed the viewer to page 2 of 2.
- Saved via Android's system Save As picker to Downloads. The provider created
  `pdfcraft-two-page (1).pdf` (934 bytes); reopening it in the app reported 2 pages, rendered, and
  navigated to page 2 again. Filtered logcat showed no Flutter fatal error or `UnsatisfiedLinkError`.
- User reports installing the APK as an app on a Galaxy S26 Ultra in India and that the device
  checks all worked. The exact Android version, ABI readout, and device logs were not provided; the
  host-side adb session used the emulator.
- Automatic builds explicitly select `android-arm64,android-x64`. A release APK inspected during
  setup had included Flutter's ARMv7 runtime without a PdfCraft library; the target-platform flag
  now prevents producing an installable artifact with that unsupported ABI.
- Local push-build automation is installed in this checkout (`core.hooksPath=.githooks`).
  `tools/build-apk.sh` produced `dist/apk/PdfCraft-Mobile-latest.apk` (83.6 MB); its SHA-256
  sidecar verified and the APK contains only ARM64/x86_64 Flutter and PdfCraft libraries. The
  pre-push hook was exercised and correctly blocked the current dirty worktree.
- `.github/workflows/android-apk.yml` runs tests and uploads a 30-day APK artifact per pushed
  commit. Its first GitHub run is pending the next push after these changes are committed.

## Verified engineering changes

- PdfCraft is pinned as a Git submodule at `dda1a155fd506cdb83dec8ead134ef57c5deda66`; relative
  Cargo paths and nested-workspace exclusion pass metadata, host test, and Android builds.
- The adapter bounds its command queue, uses upstream `Session::close`, discards timed-out opens,
  and renders through the engine-owned `RenderPool` rather than creating a second PDF renderer.
- Flutter uses system document open/Save As dialogs, requests a password after a password-related
  open error, closes the prior document after a replacement opens, and closes on viewer disposal.
- `Cargo.lock` and `pubspec.lock` are now application lockfiles and must remain tracked.

## Not verified

- Physical ARM64 Android performance/device-specific provider behavior.
- iOS: Rust target build, linking, bridge load, document provider, and device behavior.
- Password-protected PDF behavior with a real encrypted fixture; current host test passes an empty
  password to an unencrypted fixture only.
- Large-document performance, provider overwrite guarantees, and interrupted Save As recovery.
