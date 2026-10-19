# Phase 2: Manual Tool Parity & Hardening

**Target:** Audit all upstream Rust engine operations against mobile touch UIs, optimize LRU rendering memory, and harden document recovery against OOM/crashes.  
**Prerequisites:** Phase 1 complete.

---

## 1. Objectives & Deliverables
1. Audit all operations in `third_party/pdfcraft/crates/automation/src/operations.rs` against `TaskCatalog` and mobile touch sheets.
2. Complete any missing touch workflows for batch page manipulation, redaction review, form filling, OCR options, and compression.
3. Validate and tune LRU memory cache limits for large documents (100MB+, 500+ pages) to prevent Android out-of-memory (OOM) kills.
4. Harden the Storage Access Framework (SAF) URI lifecycle and auto-recovery checkpointing system.

---

## 2. Step-by-Step Implementation Instructions

### Step 2.1: Upstream Engine Operations Audit
Inspect `third_party/pdfcraft/crates/automation/src/` to ensure every operation exposed by `pdfcraft-automation` is registered in `lib/widgets/task_catalog.dart`:

| Engine Operation | Task ID | Touch Sheet / Screen | Verification Status |
| :--- | :--- | :--- | :--- |
| `page_rotate` | `page_rotate` | `lib/widgets/page_grid.dart` | Dedicated touch grid |
| `page_delete` | `page_delete` | `lib/widgets/page_grid.dart` | Selection & batch delete |
| `page_move` | `page_move` | `lib/widgets/page_grid.dart` | Drag & drop reorder |
| `page_extract` | `page_extract` | `lib/widgets/organize_sheet.dart` | Range picker & save |
| `page_insert_blank` | `page_insert` | `lib/widgets/page_grid.dart` | Add blank page |
| `doc_redact` | `doc_redact` | `lib/widgets/secure_sheet.dart` | Mark inspection & burn-in |
| `doc_ocr` | `doc_ocr` | `lib/widgets/delivery_hub_sheet.dart` | Scan & extract text |
| `doc_optimize` | `doc_optimize` | `lib/widgets/export_sheet.dart` | Target size & DPI scaling |
| `doc_encrypt` | `doc_encrypt` | `lib/widgets/secure_sheet.dart` | Password protect |
| `form_fill` | `form_fill` | `lib/widgets/form_screen.dart` | Field list & tap-to-focus |
| `signature_apply` | `signature_apply` | `lib/widgets/signature_placement_page.dart` | Drag, pinch-scale, stamp |

If any operation from `third_party/pdfcraft/crates/automation/src/operations.rs` is unrepresented, add a corresponding task definition in `TaskCatalog` with title, category, description, and input schema.

### Step 2.2: Memory Profiling & LRU Tuning
On mobile devices, rendering full PDF pages as uncompressed RGBA bitmaps at 300 DPI can consume 30–50 MB RAM per page, causing OOM kills on devices with <6GB RAM.

1. Inspect `lib/services/page_cache.dart`.
2. Configure dynamic memory bounds:
   ```dart
   // Maximum memory cache: 35% of available JVM heap or max 128 MB on mobile
   final maxCacheMemoryBytes = (Platform.isAndroid ? 128 : 256) * 1024 * 1024;
   ```
3. Implement adaptive DPI scaling in `lib/main.dart`:
   - Quick scroll / overview mode: Render at 96 DPI.
   - Reading / stationary view: Render at 150 DPI.
   - Zoomed view: Render at 200–300 DPI only for the visible viewport window, discarding off-screen zoom tiles.

### Step 2.3: Storage Access Framework (SAF) & Auto-Recovery Invariants
On Android, content provider URIs from `Intent.ACTION_VIEW` or the file picker can expire when the process restarts or loses permissions.

1. In `MainActivity.kt`:
   - Ensure `takePersistableUriPermission(uri, flags)` is executed for every `content://` URI where persistable flags are granted.
   - If non-persistable, stream incoming bytes into `cacheDir/incoming_*` immediately.
2. In `lib/main.dart`:
   - Enforce the 30-second autosave checkpoint: After any document edit, write recovery bytes to app-support directory `overline-workspace/recovery_checkpoint.pdf`.
   - On cold start, check `recovery_checkpoint.pdf` timestamp against recent documents. If a crash occurred, prompt user:
     *"Overline recovered unsaved changes from your previous session. Restore now?"*
3. Implement `_handleCloseDocument()`:
   - Always prompt: "Save changes?", "Discard", or "Cancel".
   - Never allow ghost document state or uncommitted mutations to vanish silently.

---

## 3. Verification & Acceptance Criteria
Execute the following verification commands and tests:
```bash
source tools/env.sh

# 1. Run all unit and widget tests
flutter test test/task_catalog_test.dart
flutter test test/page_grid_selection_test.dart
flutter test test/production_hardening_test.dart
flutter test test/target_compression_test.dart

# 2. Run full test suite
flutter test

# 3. Build debug APK and test on connected emulator or physical device
tools/build-apk.sh
```
Acceptance: All 50+ widget tests pass, document recovery triggers correctly on simulated process termination, and 100-page PDF scrolling consumes < 200 MB RAM.

