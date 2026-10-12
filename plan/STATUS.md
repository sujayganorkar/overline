# Project status

**Updated:** 2026-10-12
**Current milestone:** M4/M5 — shared operation layer + manual editing tools (Android verified)
**Next acceptance:** bespoke touch UIs per feature group; iOS packaging on macOS/Xcode.

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
- The bridge now hosts PdfCraft's `Automation` tool registry on its worker thread and exposes
  `operation_catalog`/`execute_tool` over FRB. The Flutter app has an Editing tools browser that
  renders every upstream tool's JSON schema as an argument form (search, destructive confirmation,
  file staging, result display, output Save As).
- On the x86_64 Android 15/API 35 emulator, four bespoke editing UIs were verified against
  real engine behavior: freehand ink annotation drawn by touch (stroke preview, `comment_add`,
  re-render shows the stroke); phrase highlight (`comment_add` highlight, yellow highlight in the
  render); form fill on an engine-generated AcroForm (text + checkbox listed, filled, and visible
  in the re-render with regenerated appearances); typed script-font signature (`fill_sign_add`,
  visible in the render); page grid with live thumbnails, blank-page insertion with live count
  update, and dirty-state propagation. Filtered logcat showed no fatal errors.
- The Comments screen was verified on the same emulator: empty state, thread list with author and
  date, nested reply display, and review-status chip update. A real tap-placement bug was found and
  fixed during testing (taps without movement never fire pan callbacks; note placement now uses
  tap-down).
- Reader interaction overhaul verified on the same emulator: the full page fits the viewport at
  open (no cropped/oversized render), left/right swipes turn pages, up/down swipes turn pages,
  pinch-zoom still pans instead of turning, the page counter opens a validated Go-to-page dialog,
  and a gesture hint is visible until the user learns it. The first swipe-turn attempt exposed the
  oversized-render bug (816px image in a ~360dp viewport); fixed with fit-scale math covered by
  `test/page_viewport_test.dart`.
- Touch-flow rework verified on the same emulator with no raw engine payloads visible anywhere:
  Edit surface lists all six actions without clipping; Pages grid supports long-press multi-select
  delete with count bar, drag-or-arrow reorder with per-move undo, and in-grid extract; highlight
  now searches first and shows a match-count/page/snippet preview before applying, with multi-page
  undo; signatures (typed and drawn) place through a tap-preview page like dates; compression
  review shows an Original/Compressed toggle with page navigation before Save As; the Agent sheet
  routes known requests to reviewed screens and declines the rest in plain words. Verified loops:
  reorder → "Undo Move page" → redo; highlight → marker on page → "Undid 1 change". No JSON, schema
  text, workspace paths, or content URIs are shown to the user; results are summarized
   (`result_summary.dart`) and files are offered through the system Save sheet. Filtered logcat
   showed no Flutter fatal errors.
- Critical audit pass 2026-10-12 (iPhone Preview docs as reference): viewer
  long-press text selection with line-snapped preview, handles, kind + color
  choice, and Apply verified with screenshots (“2 lines selected” →
  “Marked 2 selected lines”, highlight in re-render); comment creation is one
  tap (Comments + → tap page → type → list) with marker-tap opening the
  filtered thread (“Note · p1”); form fill on the generated AcroForm verified
  (“Undo Fill in newsletter”); a real redact-flow bug found and fixed (the
  dialog sent an `all` argument the engine rejects, so marking always failed
  and Apply could never succeed) — verified after fix (“Please █ in this
  form.” + undo); basic combine of two simple PDFs verified (4-page reopen).
  The   user-reported combine failure is still unreproduced and needs the
  failing inputs or exact error.
- Touch-demand pass 2026-10-12 (agents skipped): combine now includes the
  open PDF first (verified); new blank PDF creation through a confined
  bridge path (verified: 13-page reopen); viewer Copy for selections
  (verified); check/cross/dot/line marks through the tap-preview placer
  (verified); insert-pages-from-file and page-image export in UI with new
  Rust coverage for `page_insert_file`, `doc_export_images`, check marks,
  and blank creation (image export verified on device: PNG saved).
  Remaining touch gaps: drag-crop UI, stamps, scan-to-PDF (needs camera),
  OCR models (blocked), compare-report Save As.
- Flow optimization #1 (2026-10-12): saved-signature reuse — the most
  recent typed name and drawn PNG persist in app-private storage; the
  chooser offers them first and jumps straight to placement. Verified on
  device (type once → “Use …” row → placement). Covered by
  `test/signature_store_test.dart`. Copy-selection, blank-PDF creation,
  check/cross/dot/line marks, insert-from-file, and page-image export from
  the same pass are likewise verified (device and/or Rust tests).
- Full touch-redesign pass (2026-10-12, `plan/TOUCH_REDESIGN_PLAN.md`):
  grouped Annotate toolbar with stamp/picture tap modes and measured-value
  feedback; Create/Pages/Stamp + Convert/Improve/Review + Redact/Clean/Lock
  + Saved/Create/Marks sections; real header/footer dialog, watermark
  opacity/behind, background presets, remove-marks row; compare-report
  Save As; measurements export; form reset + values import/export; crop
  page by drag box; links manager; replace-selected-pages; demand-ordered
  Edit sheet; one-time gesture coach with neutral Ready status; agent
  done-snackbar. Device-verified: stamp, crop, picture, yellow tint,
  links add/list, sections, coach. Host-tested: report, replace, reset,
  measure export, remove-marks, header/footer+watermark options,
  insert-file, check mark. Two audit bugs fixed along the way
  (`_execute` ignoring its tool arg; summary staging path offered as a
  fake Save As result).

## Verified engineering changes

- PdfCraft is pinned as a Git submodule at `dda1a155fd506cdb83dec8ead134ef57c5deda66`; relative
  Cargo paths and nested-workspace exclusion pass metadata, host test, and Android builds.
- The adapter bounds its command queue, uses upstream `Session::close`, discards timed-out opens,
  and renders through the engine-owned `RenderPool` rather than creating a second PDF renderer.
- Flutter uses system document open/Save As dialogs, requests a password after a password-related
  open error, closes the prior document after a replacement opens, and closes on viewer disposal.
- `Cargo.lock` and `pubspec.lock` are now application lockfiles and must remain tracked.

## Not verified

- Physical ARM64 Android run of the new automation-backed build (prior viewer build passed on a
  Galaxy S26 Ultra; re-test the editing build on-device when convenient).
- iOS: Rust target build, linking, bridge load, document provider, and device behavior.
- Password-protected PDF behavior with a real encrypted fixture; current host test passes an empty
  password to an unencrypted fixture only.
- OCR tools need downloadable models; not exercised on device.
- Bespoke per-feature touch UIs (finger drawing canvas, form widgets, signature pad) beyond the
  schema-driven operation browser.
