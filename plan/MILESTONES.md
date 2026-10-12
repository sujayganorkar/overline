# Engineering milestones

The first product MVP is the complete agreed **manual PDF editing** scope plus the first reviewed
task workflows. Features arrive in verified slices, but the MVP is not reduced to a reader plus a
few edits. Status means demonstrated evidence, not code presence; current results are in
[`STATUS.md`](STATUS.md).

## M0 — reproducible foundation (complete)

- Pin PdfCraft to a known upstream commit and use relative paths.
- Pin Flutter/Dart, Rust dependencies, and bridge code generation.
- Document Android SDK/NDK setup and preserve required upstream notices.
- Pass Rust tests, Flutter analysis/tests, Android native builds, and APK packaging.

## M1 — Android PDF viewer vertical slice (emulator and physical phone verified)

Acceptance: select an actual local PDF; PdfCraft opens it; show page count; render and navigate real
pages; use system Save As; reopen and render the saved output; cover malformed input and lifecycle.
Capture device/API/ABI and exact commands.

The full flow passed on the x86_64 Android 15/API 35 emulator. The user also reports installing the
APK on a Galaxy S26 Ultra in India and that everything worked; exact Android version/ABI/log details
were not captured in this session. iOS is not yet built.

## M2 — document I/O, lifecycle, and safety

- Validate provider URIs, Save As cancellation, overwrite/duplicate behavior, interrupted writes,
  password errors, and reopen on supported platforms.
- Test repeated open/close, worker shutdown, stale/timed-out requests, and malformed PDFs.
- Establish budgets for memory, render latency, and large documents; test app background/resume.
- Define saved/dirty state and the smallest recoverable-work behavior required for the editor MVP.

## M3 — complete reading workflow

Finish responsive page navigation, zoom/pan, search and text extraction, and lazy/adaptive rendering.
Test multi-page documents and resource limits on phones and tablets. The current full-page PNG path
is only a proof of integration; choose production rendering based on device measurements.

## M4 — shared deterministic operation foundation

Implemented: the bridge exposes PdfCraft's existing automation tool registry (stable IDs, JSON
schemas, read-only/destructive flags, command links) through `operation_catalog`/`execute_tool`,
with document status (dirty, editable, undo/redo) on every mutating result. Manual UI calls the
same handlers future agents will call. No agent loop, model integration, or arbitrary JSON-to-PDF
path exists.

## M5 — manual PDF editor product MVP (in progress)

In progress: the four Read / Edit / Organize / Agent surfaces and the persistent canvas command
button route to reviewed touch flows and the shared operation registry. Bespoke interaction flows
now include multi-select page deletion, image-to-PDF with reorder, date preview/place/undo,
target-size compression, compare-and-mark, recipes for dates/phone redaction, form detail matching,
extractive summary/evidence, autosave/recovery, share, and batch OCR when models are installed.
Host Rust and Flutter checks pass; the Android release APK builds for ARM64/x86_64. Physical-device
verification of these newest flows, OCR model installation, encrypted-fixture password tests, and
iOS packaging/validation remain acceptance work.

Complete the full manual capability set from [`PRODUCT.md`](PRODUCT.md), in testable sub-slices:

1. **Markup:** highlights, comments/annotations, freehand/stylus drawing, text insertion, and
   existing-text editing where PdfCraft supports it reliably.
2. **Pages and files:** insert/delete/reorder/rotate, merge/split, export/share, and compression.
3. **Forms and signatures:** inspect/fill fields and create/use signatures.
4. **Scanned and converted documents:** mobile-compatible OCR and supported format conversion.
5. **Reliability:** undo/redo, dirty state, safe saves/reopen, and recovery for the supported edits.

Every capability must use the shared operation layer, be called from the manual UI, have a bridge
and save/reopen test, and be verified on-device. Audit engine support and licenses before promising
any item. The MVP is not called complete until the agreed manual list is covered.

The product is intended for Android and iOS. Android is the lead implementation platform; before
claiming a cross-platform MVP, build and validate the same manual capabilities on macOS/Xcode and
real iPhone/iPad document providers.

## M6 — optional local model runtime

After the manual operation set and reviewed deterministic workflows are stable, evaluate licensed
on-device models/runtimes for broader request-to-operation mapping. Add a constrained planner,
previews/confirmation for destructive actions, and execution through the existing operation registry.
Core editing remains fully usable without the model or network.

## M7 — optional premium cloud intelligence

Only after user demand and product validation: consent-first processing, explicit paid usage,
server-side authorization/accounting, retention/privacy controls, and the same constrained operation
interface. Cloud infrastructure is outside the manual MVP.
