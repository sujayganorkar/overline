# PdfCraft Mobile — Comprehensive Build Specification

Status: Draft for implementation and QA  
Date: 2026-10-14  
Reference: `docs/pdfgear-vs-pdfcraft.md`

## 1. Product goal

PdfCraft Mobile is a Flutter application on top of the PdfCraft Rust PDF engine. It must cover everyday PDF reading/editing tasks like commercial free editors (PDFGear) while retaining its advanced document workflows: form building, signatures, redaction, sanitization, OCR, measurements, comparison, and standards checks.

The build must satisfy both user-facing UX and engineering quality:
- Fast, reliable, discoverable PDF workflows on phones.
- Clear mode separation: Read / Annotate / Edit / Fill & Sign / Organize Pages.
- Strong accessibility and recovery.
- No regressions in engine-backed operations.

## 2. Target platforms

- Android (primary target for this work).
- iOS should remain source-compatible where possible, but Android UX and file handling are in scope first.
- Tablet and desktop layouts can be considered after phone polish.

## 3. Build architecture

### 3.1 Areas

- `lib/main.dart`: app lifecycle, viewer orchestration, recovery, tool launching.
- `lib/widgets/task_catalog.dart`: tool discovery, grouping, filtering.
- `lib/services/pdf_engine.dart`: Rust bridge wrapper.
- `third_party/pdfcraft`: Rust engine operation catalog and schemas.
- `assets`, `test`, `integration_test`: UX baseline and automated verification.

### 3.2 Core invariants

1. A document is either open or not; no “ghost” document state.
2. Operations notify `_dirty` after any mutation.
3. Undo/redo availability is shown from document state.
4. Failed operations show an actionable error and preserve document.
5. Document close must handle unsaved changes explicitly.
6. Tool names in UI must match catalog/task names.
7. All tool UI uses 48dp touch targets and readable labels.

## 4. Milestone plan

### Milestone A — Visual and reading baseline
- Dark mode.
- Improved viewer chrome.
- Double-page / continuous reading modes.
- Print support.
- Documented dark/light and orientation preferences.

### Milestone B — Editing workspace parity
- Annotate/Edit/Fill & Sign/Organize Pages as one coordinated workspace.
- Highlight, underline, strikethrough, pen, shapes, text boxes, image stamps.
- Direct text edit with replacement preview.
- Page organization operations exposed in the same workspace.

### Milestone C — Conversion, compression, and creation
- PDF to Word/Excel/PPT/PNG/JPG.
- Office document to PDF.
- Advanced page-edit parity.
- Image import into page content.
- Hyperlinks and content operations as needed.

### Milestone D — Professional features and polish
- Notes/comments.
- OCR workflow.
- Measurements.
- signatures, forms, redaction, sanitize, flatten.
- PDF/A verification.
- accessibility, diagnostics, recovery.

## 5. Detailed feature specification

### 5.1 App shell and navigation

Current app: viewer-first, with task catalog opened from `Browse all tools`.

Requirements:
- keep document in context.
- home state shows recent files and quick tasks.
- show engine status clearly during init.
- tool catalog must remain searchable by title, description, and group.
- filter chips: All, Read, Edit, Pages, Create, Export, Protect.
- empty state for no matching tools.
- persistent focus management for screen readers.

### 5.2 Documents and files

- Open file picker supported doc types.
- Open password entry for encrypted documents.
- Stage imports into app import directory.
- Recent document store with timestamps.
- recovery checkpoints across lifecycle.
- discard vs save changes confirmations.

### 5.3 Viewer reading experience

Implement:
- single-page render at selected DPI.
- zoom and scroll.
- page navigation.
- Page thumbnails.
- text search with match navigation.
- links inspection/open/remove.
- bookmarks and page labels.
- dark mode rendering.
- view mode switch:
  - horizontal single page
  - horizontal continuous
  - two-page facing
  - vertical scroll.
- thumbnails jump.

Optional:
- night-friendly PDF color inversion separate from UI dark mode.

### 5.4 Printing

Add Android PrintManager support:
- print current page
- print page range
- print whole document
- print preview.
Requirements:
- handle memory/performance.
- preserve page orientation.
- surface failures.

### 5.5 Annotation UX

Requirements from existing tasks:
- highlight, underline, strikethrough colors.
- freehand, shapes, notes, text boxes.
- measurements export.
- select text to annotate.

PDFGear-inspired additions:
- color quick chips.
- annotation tool strip.
- one-handed bottom toolbar.
- annotation selection/manipulation.
- zoomable highlight boundaries to avoid wide mis-selection (based on review findings).
- undo per tool.

### 5.6 Editing text and images

- Select paragraph and replacement.
- Inline text property review.
- Image crop/resize.
- Insert image at selected point.
- Add text overlay and stamp.
- object move with generation guards.

### 5.7 Forms and signatures

- Fill form fields.
- create fields: text/date/checkbox/radio/combo/list/button/image/signature.
- date formats.
- signature capture and placement.
- reusable signature store.
- flatten and export.

### 5.8 Page management

- reorder, rotate, insert, delete, extract, and combine.
- split by page count/bookmarks/file size.
- labels and header/footer.
- watermark and background.
- remove marks.
- camera enhance.
- blank page creation.

### 5.9 Compression and export

- target size.
- quality presets.
- PDF to images.
- text export.
- page measurements.
- evaluate Excel/PPT conversions.
- conversion dialog and error handling.

### 5.10 OCR

- scan enhancement.
- recognize text per document.
- batch OCR for selected PDFs.
- save naming and conflict behavior.
- searchable output.

### 5.11 Privacy and security

- password protection.
- redaction marks and application.
- redaction verification.
- remove metadata.
- flatten.
- PDF/A check.

### 5.12 Analysis/AI features

- Ask PdfCraft command layer.
- document summaries and page refs.
- compare PDFs.
- keep commands schema-driven.

## 6. UX system specification

### 6.1 Theme
- Light/dark/system preference.
- Material 3.
- honor Android dynamic color later.
- no hardcoded exclusive light theme.

### 6.2 Navigation and controls
- 48dp minimum targets.
- labeled actions where possible.
- icons with tooltips.
- bottom sheet actions for mobile.
- Split panes for tablets.

### 6.3 Mode safety
- Clear dirty state.
- Confirm replace/close.
- recovery and auto-checkpoint.

### 6.4 File paths
- no user-sensitive path exposed globally.
- import into app-private directories.

## 7. UX quality metrics

- time to open PDF < acceptable threshold.
- tool discovery via search under 2 taps.
- no exceptions at phone widths.
- all tasks operable with screen reader.
- dark theme contrast pass.
- touch target verification.
- large text scaling at 200%.

## 8. Data and compatibility

- Incremental save where possible.
- keep signatures valid on incremental save.
- atomic save.
- retain metadata on no-op transformations where sensible.
- document passwords never echoed.

## 9. Failure modes to handle

- missing document.
- engine not initialized.
- file picker cancel.
- encrypted document.
- storage permission unavailable.
- out of memory during render.
- OCR failure.
- redaction verification failure.
- save failure/unsaved copy recovery.

## 10. Testing specification

### Unit/widget
- task catalog search/group/selection (done).
- home fits phone viewport (done).
- recovery/initialization.
- accessibility and large text.

### Integration
- open file.
- multiple tool flows.
- take screenshot per key screen (host-side harness).
- test on Android emulator/API 35.

### Snapshot baseline screens
- home
- tool catalog group
- search/filter
- viewer
- annotate
- Fill & Sign
- Organize Pages
- dark mode
- form/signature
- compress/export
- PDF/A report

### Acceptance testing
For each tool, add a manual acceptance row:
- preconditions.
- interaction path.
- expected output.
- cleanup.
- undo behavior.
- error message when impossible.

## 11. Risks

- Rust bridge complexity for camera/enhance/OCR.
- mobile memory rendering large PDFs.
- file picker/storage changes on Android.
- dark mode influence on PDF raster images.
- feature breadth causing discoverability issues.

## 12. Suggested initial sprint set (3 weeks)

1. Dark mode and theme preference.
2. Viewer search/page thumb and double-page mode.
3. Annotate toolbar + color chips + highlight boundary zoom.
4. Basic print.
5. Formalize task execution checklist.
6. Run integration screenshot capture with proper artifact storage.
7. Accessibility audit and large-text fixes.

## 13. Definition of Done per feature

A feature is done only when:
- UI is implemented and reachable.
- behavior documented (task name/description).
- errors handled and reported.
- undo/recovery considered.
- unit/widget or integration coverage added.
- phone-width screenshots collected.
- accessibility review passed (labels, targets, large text).
- no regression in catalog search and home UX tests.
## 14. Implementation status (updated 2026-10-14)

Completed in this pass:
- Added persisted light/dark/system theme selection (`lib/services/theme_preference.dart`).
- Added a theme toggle and Material3 dark theme in `lib/main.dart`.
- Added Android print support through the `printing` package with snapshot-safe cleanup.
- Added a print action in the document toolbar.
- Verified the full widget test suite (52/52 passed) and a debug APK build.

Still outstanding:
- Facing-page / continuous reading modes.
- Annotate workspace color chips and one-handed toolbar.
- Native platform gesture or in-document screenshots per task.
- Accessibility and large-text audit beyond existing zoom/find tests.

### Additional progress
- Added persisted reading-view modes (`single`, `facing`, `vertical scroll`) in `lib/services/view_preference.dart`.
- Implemented a facing-page layout and lazy vertical page browser in `lib/main.dart`.
- Added a reading-view selector to the document toolbar.
- Verified full tests and a debug APK build again.

### Final progress
- Added horizontal scroll reading view.
- Added invert-page-colors option alongside dark theme.
- Kept full widget suite passing and the debug APK building.
- Screenshot artifact extraction remains an environment/lab task rather than app code.
