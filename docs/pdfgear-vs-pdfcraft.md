# PDFGear vs PdfCraft Mobile — feature and UX comparison

Date: 2026-10-14
Local app under test: `com.pdfcraft.pdfcraft_mobile` (Flutter UI over the PdfCraft Rust engine)
Comparator: `com.pdfeditor.pdfeditorandriod` (PDFGear: PDF Editor & Reader, Google Play listing)

## Test setup actually completed

- Android emulator used: `pdfcraft` AVD (Pixel 7, Android 35, `google_apis`, x86_64).
- Our app launched successfully on the emulator: `com.pdfcraft.pdfcraft_mobile/.MainActivity`.
- A sample PDF was pushed to `/sdcard/Download/sample.pdf` and delivered to the running app through an `ACTION_VIEW` intent.
- Home/tool-catalog screenshots were captured from the emulator; this confirms the app starts and the tool browser opens at phone widths.
- PDFGear itself could not be installed onto the same emulator. The AVD has the `com.android.vending`/LicenseChecker stub rather than a working Play Store, and third-party mirrors required an interactive Cloudflare Turnstile solve that could not be completed non-interactively. Therefore PDFGear was compared using its verified Google Play listing, official feature description, and current listing screenshots rather than an on-device binary.

## Executive summary

PDFGear is a consumer-first, free, broad-coverage PDF app with strong reading/viewing ergonomics (double-page mode, native dark mode, print, recent files, thumbnails) and a compact, self-contained operation set. PdfCraft Mobile is a deeper document toolchain: it has far broader engine-level editing (structured text/object moves, forms creation, signatures, redaction/sanitization, OCR, page labels, header/footer, watermark, background, measurements, compare-documents, PDF/A checks) and multiple routing entry points, but it currently lacks several everyday reader conveniences that PDFGear markets prominently (double-page reading mode, native dark mode, direct printing, easy image insertion into page content, Office-to-PDF/PDF-to-Excel/PDF-to-PowerPoint conversion).

Bottom line: PDFGear is easier and friendlier for common mobile PDF reading and light editing; PdfCraft has more professional/PDF-power-user capabilities, but its UX can feel more technical and tool-heavy.

## Feature parity matrix

Legend: ✅ present, ➖ partial/indirect, ❌ not found in our app, ➕ ours has more/stronger

### Viewing and reading

| Capability | PDFGear | PdfCraft Mobile | Notes |
|---|---:|---:|---|
| Single-page view | ✅ | ✅ | Both render pages as images. |
| Double-page / facing-page mode | ✅ | ❌ | PDFGear explicitly supports it; our viewer is single page. |
| Page thumbnails / page grid | ✅ | ✅ (`page_grid`) | Both allow visual page management. |
| Zoom in/out | ✅ | ✅ (`zoom_controls`, pinch/swipe handling) | Ours has transform controller and swipe handling. |
| Native dark mode | ✅ | ❌ (theme is light only) | Our app uses a fixed light color scheme. |
| Open recent documents | ✅ | ✅ (`recent_documents_store`) | Parity. |
| Text search with precise locations | ✅ | ✅ (`find_bar`, `text_find`) | Both locate matches by page. |
| Print directly from device | ✅ | ❌ | No printing code path found. |
| Basic reading status / page numbers | ✅ | ✅ | Both track current page. |

### Annotation and markup

| Capability | PDFGear | PdfCraft Mobile | Notes |
|---|---:|---:|---|
| Highlight text | ✅ | ✅ (`selectText`, highlight color) | Ours supports selectable color. |
| Underline / strikethrough | ✅ | ✅ | Parity. |
| Custom annotation colors | ✅ user-defined | ✅ color strings/colors | Parity. |
| Rectangles, circles, lines, arrows, freehand | ✅ | ✅ (`quick_mark_page`, draw task) | Ours also has measurements. |
| Text boxes / notes | ✅ font size and color | ✅ comments and annotations | Parity or better depending on editability. |
| Bookmarks | ✅ view/add/rename/delete/expand-collapse | ✅ (`bookmarks_screen` + bookmark tools) | Ours supports move and set page too. |
| Comments / threaded notes | ➖ (notes) | ✅ (`comments_screen`) | Ours has reply/manage note affordances. |
| Measurement readings export | ❌ | ✅ (`measurements` task) | Ours unique. |

### Editing content

| Capability | PDFGear | PdfCraft Mobile | Notes |
|---|---:|---:|---|
| Edit text content (add/remove words/paragraphs) | ✅ | ✅ (`text` task, engine text tools) | PDFGear is more direct; ours often stages replacements. |
| Edit text properties / fonts | ✅ | ✅ object/text operations | Parity. |
| Resize / crop images | ✅ | ✅ (`crop_page`, object move) | Ours crop is page-level, not necessarily embedded-image resize. |
| Insert new images into page content | ✅ | ➖ (stamps/image form fields possible; no simple “add image” tool) | Gap for casual users. |
| Sign and date | ✅ | ✅ (`signature_pad`, placement, store, flatten) | Ours is more complete and repeatable. |
| Fill forms | ✅ listing mentions | ✅ (`forms` task) plus creating/editing form fields | Ours has greater form-building depth. |
| Move selected objects together | ➖ | ✅ (`object_move`, generation-guarded) | Ours unique/strong. |

### Page management

| Capability | PDFGear | PdfCraft Mobile | Notes |
|---|---:|---:|---|
| Merge PDFs | ✅ | ✅ (`combine`, `doc_create_multiple`) | Parity. |
| Split PDFs | ✅ | ✅ (`split` by pages/size/bookmarks) | Ours offers bookmark/size splitting. |
| Append pages from another PDF | ✅ | ✅ (`page_insert_file`) | Parity. |
| Insert blank pages | ✅ | ✅ (`page_insert_blank`) | Parity. |
| Extract pages | ✅ | ✅ (`extract`) | Parity. |
| Rotate pages | ✅ | ✅ (`page_rotate` with subset/orientation) | Ours has advanced filtering. |
| Reorder / delete pages | ✅ | ✅ (`pages`, reorder UI) | Parity. |
| Page labels / numbering | ➖ (page numbers as header/footer?) | ✅ (`labels`, page_number) | Ours explicit. |
| Header/footer text and page numbers | ➖/unknown | ✅ (`headerFooter`) | Strong extra. |
| Watermark | ➖/unknown | ✅ (`watermark`) | Strong extra. |
| Page background color | ❌ listed? | ✅ (`background`) | Ours extra. |
| Remove headers/footers/watermarks | ❌ listed? | ✅ (`removeMarks`) | Ours extra. |
| Enhance scanned/camera pages | ➖/unknown | ✅ (`page_enhance_camera`) | Ours unique. |

### Conversion and export

| Capability | PDFGear | PdfCraft Mobile | Notes |
|---|---:|---:|---|
| PDF to Word / DOCX | ✅ | ✅ (`office` → Word/RTF/HTML) | Parity-ish. |
| PDF to Excel | ✅ | ➖ (measurements spreadsheet only) | Gap. |
| PDF to PowerPoint | ✅ | ❌ | Gap. |
| PDF to PNG/JPG | ✅ | ✅ (`exportImages`) | Parity. |
| Create PDF from Word/Excel/PPT | ✅ | ➖ (images/text/PDF via combine; not Office docs) | Gap for Office inputs. |
| Create PDF from images | ✅ | ✅ (`images`, combine) | Parity. |
| Export text | ✅/likely | ✅ (`exportText`) | Parity. |
| Reduce/compress file size | ✅ | ✅ (`compress`, `compressionPresets`) | Ours adds target KB/MB and presets. |

### Security, privacy, and standards

| Capability | PDFGear | PdfCraft Mobile | Notes |
|---|---:|---:|---|
| Add open/edit password | ➖ (not listed on mobile Play description) | ✅ (`protect`) | Ours explicit. |
| Redaction marking | ❌ listed? | ✅ (`redact`, `secure`) | Ours unique. |
| Apply/clear redactions, verification | ❌ listed? | ✅ (`secure`, sanitize) | Ours unique. |
| Remove metadata/hidden information | ❌ listed? | ✅ (`sanitize`) | Ours unique. |
| Flatten fields/comments | ❌ listed? | ✅ (`flatten`) | Ours unique. |
| Check PDF/A archival suitability | ❌ listed? | ✅ (`verify`) | Ours unique. |
| Forms building (create fields) | ➖ (fill only?) | ✅ (`form_screen`, form field tools) | Ours much broader. |

### Search, AI, and analysis

| Capability | PDFGear | PdfCraft Mobile | Notes |
|---|---:|---:|---|
| AI copilot / Q&A / summarization | ✅ tagline (“AI copilot”) | ✅ (`agent` “Ask PdfCraft”, `insights`, `compare`) | Different depth; PDFGear’s AI is more consumer-facing, ours exposes structured evidence and page refs. |
| Compare two PDFs | ❌ listed? | ✅ (`compare`) | Ours unique. |
| Recognize scanned text (OCR) | ➖/unknown (desktop has) | ✅ (`ocr`, `ocrBatch`, enhance camera) | Ours strong on mobile. |

### Operation catalog / automation

| Capability | PDFGear | PdfCraft Mobile | Notes |
|---|---:|---:|---|
| Tool browser/search/grouping | Basic app menu | ✅ (`TaskCatalog`: search + 7 groups) | Ours has 36+ tasks in clear groups. |
| Repeatable mobile document operations | Basic | ✅ engine `operation_catalog` | Ours has stricter schemas and undo-oriented commands. |

## UX flow comparison

### Opening and home experience
- PDFGear: simple home; official screenshots emphasize immediate reading and a compact toolbar. Strong empty-state/recent-doc convenience and conventional mobile “tap to open” behavior.
- PdfCraft: viewer-first home with status line, engine initialization, recent documents, document title, dirty state, undo/redo, update/recovery, and a “Browse all tools” sheet. More informative but more cognitively loaded; on a phone, most of the vertical space immediately goes to page rendering plus toolbar.

### Navigation within a document
- PDFGear: single- or double-page display, thumbnail preview, zoom, text search, dark mode; reader-centric.
- PdfCraft: single-page viewport, page grid available as a task, find bar; strong for editing workflows, weaker for relaxed reading because no spread mode or dark mode.

### Annotating
- PDFGear: markup by selecting text directly; shape tools and text boxes; natural color choices.
- PdfCraft: annotation is task-driven: select text, choose color/kind, apply; freehand notes; also comments and measurement capture. Powerful but more modal.

### Editing
- PDFGear emphasizes direct text editing and image crop/insert, which is the most relatable mobile editing story.
- PdfCraft asks for replacement-oriented “edit text” and object moves; it is safer and more structured but less WYSIWYG.

### Page operations
- PDFGear covers merge/split/insert/blank/extract/rotate/reorder/delete.
- PdfCraft covers all of those plus labels, header/footer, watermark, background, remove marks, extract measurements, and splitting by bookmark or file size. This is a clear win.

### Forms and signatures
- PDFGear lets users fill/sign documents; less is documented about building forms.
- PdfCraft has form filling plus full form-field creation (text, date, checkbox, radio, combo, list, button, image field, signature) and reusable signature storage/placement. This is a clear win.

### Privacy and security
- PDFGear: no ads claimed; generic privacy statement.
- PdfCraft: explicit password protection (by tool), redaction, sanitization, flatten, PDF/A verification. This is a clear win for sensitive documents.

### AI
- PDFGear markets an “AI copilot” (likely chat/summarization) but mobile feature list is thin.
- PdfCraft has “Ask PdfCraft” plus summary/excerpt insights and document comparison. More inspectable/explainable, but less consumer-chat oriented.

## On-device PDFGear UX findings (new)

After manual installation of `com.pdfeditor.pdfeditorandriod` on the same `pdfcraft` AVD, the following flows were exercised by automating/observing the UI:

Home / file browser
- Home is a file hub, not a viewer: cards for **Files**, **Photos**, **Trash**, search field, and a bottom nav with **Files / Recents / Settings**.
- PDFGear home emphasizes recent files (`mobile-1-combine-a.pdf` etc.) and has a floating “+” add action. This is friendlier as a document hub than our viewer-first entry.
- Permission flow is explicit on first launch (storage-like permission dialog).

Viewer toolbar
- Top bar exposes **Edit**, an AI button, **Search**, **Bookmarks**, and a **More** menu (**View Settings**, **Go to Page**, **Convert**, **Share**, **Print**, **Save as**, **OCR**).
- This toolbar is compact but icon-driven; several functions are not labeled until tapped. Our app tends to expose more labeled task text, which is more explicit but heavier.

View settings
- PDFGear supports **Horizontal/Vertical** layouts plus **light/dark view toggles** directly in a bottom sheet. This confirms its native dark-mode/reading ergonomics and is a concrete gap in PdfCraft (light theme only).
- Dark/light toggles and horizontal/vertical controls are visually simple and quick.

Edit mode
- Edit mode exposes four working modes: **Annotate**, **Edit**, **Fill & Sign**, **Organize Pages**, then **Done**.
- A horizontal annotation tool strip appears in annotate mode, suggesting tool-first layout rather than our task-first list.
- Exit is a single **Done** button, which keeps the user in document context.

Print and OCR
- Both **Print** and **OCR** appear in the More menu, confirming two gaps/strength comparisons:
  - PDFGear has direct print from mobile.
  - PDFGear also surfaces OCR from the viewer.
  - PdfCraft has OCR too, so this is closer to parity than printing.

## Additional on-device PDFGear audit findings ( deeper pass)

### Reader and navigation
- **Search** is a top-bar icon (`vw_search`) with text input; the opened search context was not fully represented in the accessibility tree, so it appears to use a custom overlay/search flow.
- **Bookmarks/TOC** opens as a sheet titled “Table of Contents”; empty documents show “No table of contents in this PDF”, plus a **Close** action.
- **Go to Page** is a small dialog with page number entry (`Enter Page Number (1-9)` for this document), **OK**, **Cancel**, and an `Edit` option.
- **View Settings** sheet exposes:
  - horizontal / vertical reading layout
  - light / dark view toggle
  - likely zoom/fit options represented as bottom circular controls

### Edit workspace design (icon-level audit)

In annotate mode, the top strip contained **10 icon tool slots** (indices 0-9).
- Slot 0: selected by default when annotate mode opens.
- Slot 1 (tap): revealed **Highlight + Color** labels.
- Slots 2-9: icon-first drawing tools (underlines/strikethrough/stamps/shapes are not labeled in the current accessibility tree, so their exact behavior would require visual inspection).

Fill & Sign mode exposed **5 tool slots** plus Redo/Undo and More.
Organize Pages mode exposed selection-aware actions:
- **Selected / All**
- numbered page selectors
- Done

### Edit workspace design
PDFGear’s edit workspace is a good reference for interaction:
- Top `Edit` button enters a persistent annotation/edit mode.
- A mode switcher panel (triggered from `vw_edit_model`) exposes four families:
  - **Annotate**
  - **Edit**
  - **Fill & Sign**
  - **Organize Pages**
- In **Annotate**, a horizontal strip shows many annotation tool choices (icon-first, compact).
- In **Edit**, the toolbar exposes:
  - **Text**
  - **Add Text**
  - **Image**
  plus a Redo/Undo grouped control and More.
- In **Fill & Sign**, the toolbar shows five tool slots plus Redo/Undo and More.
- In **Organize Pages**, the toolbar emphasizes selection:
  - **Selected / All**
  - numbered page selection (1-4)
  - Done
- **Done** exits edit mode and returns to normal reading.

This suggests PDFGear uses a single edit workspace with mode/feature switching, while PdfCraft uses a broader task catalog. PDFGear’s model is faster for adjacent tasks, while PdfCraft’s model scales better for advanced tools.

### More menu
The reader More menu exposes:
- View Settings
- Go to Page
- Convert
- Share
- Print
- Save as
- OCR (may open save-location selection / save flow)

Convert opens a “Convert to…” dialog listing:
- Microsoft Word (*.doc, *.docx)
- Microsoft Excel (*.xls, *.xlsx)
- Microsoft PowerPoint (*.pptx)
- PNG (*.png)
- JPG (*.jpeg)
- Rich Text Format (*.rtf)

OCR opens a save-location picker with a **SAVE** button and file browser, confirming it runs as a save-oriented operation.

### Home/file hub
- Home uses **Files / Photos / Trash** plus a floating add action and bottom **Files / Recents / Settings**.
- The same file list shows recents with size and date labels.

## PdfCraft task-by-task hands-on execution checklist

This checklist is the practical deep-audit baseline for PdfCraft. It breaks every catalog task into a user-facing interaction objective and a verification target. Items marked �Source-verified� are confirmed from the task catalog/engine/mappings; they can be clicked through manually or with an instrumented Flutter test.

Category – task – entry action – expected screen/observation – verification
Read
- `find` – tap tool / enter query – find bar with matches – result count and match rectangles.
- `bookmarks` – tap tool – bookmarks sheet – outline list + add/rename/delete/move actions.
- `comments` – tap tool – comments screen – read/reply/manage notes.
- `insights` – tap tool – summary/evidence sheet – excerpts with page references.
- `links` – tap tool – links screen – inspect/open/remove links.
- `compare` – tap tool + second doc – comparison view – differences and navigation.
- `agent` – tap tool – Ask PdfCraft sheet – suggested plan + execution.

Edit
- `sign` – tap tool – signature pad + placement – signature item appears.
- `forms` – tap tool – fill form screen – field read/write.
- `draw` – tap tool – annotate page / quick mark – ink/shapes/measurement capture.
- `selectText` – tap tool – line selection mode – highlight/underline/strikethrough.
- `highlight` – tap tool – search-driven highlight review – matching phrase locations.
- `text` – tap tool – edit text sheet – replacement preview and application.
- `redact` – tap tool – redaction finder – candidate marks.
- `secure` – tap tool – security review screen – apply/clear redactions.

Pages
- `pages` – tap tool – page grid – reorder/rotate/crop/insert/delete controls.
- `split` – tap tool – split sheet – output files.
- `extract` – tap tool – page selector – new PDF.
- `labels` – tap tool – labels sheet – numbering resume behavior.
- `headerFooter` – tap tool – header/footer sheet – text/page-number placement.
- `watermark` – tap tool – watermark sheet – text overlay.
- `background` – tap tool – color picker – page background.
- `removeMarks` – tap tool – mark removal controls.
- `page text/check commands` (object moves, etc.) – task surfaces, engine commands – tool schema and generation guards.

Create
- `images` – tap tool – file order sheet – combined PDF result.
- `combine` – tap tool – file order sheet – one PDF.
- `blank` – tap tool – page size entry – blank doc.

Export
- `compress` – tap tool – target size/KB/MB sheet.
- `compressionPresets` – tap tool – preset list.
- `office` – tap tool – export dialog (Word/HTML/RTF).
- `exportImages` – tap tool – format/PNG/JPEG selection.
- `exportText` – tap tool – save dialog.
- `measurements` – tap tool – readings/export spreadsheet.
- `ocr` – tap tool – recognize text for current doc.
- `ocrBatch` – tap tool – batch OCR queue.
- `verify` – tap tool – PDF/A check report.

Protect
- `protect` – tap tool – password dialog.
- `sanitize` – tap tool – metadata removal controls.
- `flatten` – tap tool – interactive-content flatten controls.

Cross-cutting
- onboarding/home cards: Open PDF, Create from photos, Start blank, Combine.
- recent docs restore.
- undo/redo and recovery checkpoint.
- error/status messaging.
- tool catalog search/filter accessibility.
- large text/scaling support (verified in test).

## Mobile/UX quality observations from our app test

These are based on the installed app test and source review:
- App starts successfully and opens a real PDF through Android intent; engine initializes as “PdfCraft Rust core”.
- The UI is viewer-centric with a large top app bar and a “Browse all tools” entry; this avoids a separate home screen and keeps context on the document.
- At a narrow phone viewport (390×844), the home/tools flow was tested and passes (`test/ux_preview_test.dart`).
- The tool catalog is searchable and grouped (All/Read/Edit/Pages/Create/Export/Protect), which is a good navigation model when the feature set is large.
- Search is available both as text find and in the tool catalog.
- There is no dark mode, no double-page reading mode, and no printing path — three of the most user-visible gaps against PDFGear’s marketing.
- Error handling/recovery exists (`recovery checkpoint`, `confirmReplacingCurrent`, status lines), which improves UX for long editing sessions.

## Recommendations to close the gap vs PDFGear

High impact:
1. Add native dark mode (Material 3 supports it; our theme hardcodes a light scheme).
2. Add printing via Android Print framework (`PrintManager`/`PrintHelper`).
3. Add a spread/double-page reading mode and optional continuous scroll mode.
4. Add a simpler image insertion flow (“insert image at cursor/page”) rather than relying on stamps/form fields.
5. Add PDF → Excel and PDF → PowerPoint export, or at least tabular extraction to XLSX.
6. Add Office document → PDF creation to match PDFGear’s conversion matrix.
7. Make text edits more interactive (select paragraph → inline replace preview) rather than only command-style replacement.

Medium impact:
8. Provide a compact reader mode with thumbnail strip and recent-doc grid; link common tools from the viewer toolbar.
9. Add keyboard/soft-keyboard-aware “save as” filename handling (review note: PDFGear users hit the keyboard overlap problem).
10. Add highlight boundary zoom/snapping to solve the wide-range highlight usability issue noted in PDFGear reviews — a good differentiator.
11. Clarify AI feature naming/capabilities and give an always-visible “summarize this document” entry point.

Low risk / keep as strengths:
- Keep redaction, sanitize, flatten, PDF/A check, OCR, measurements, comments, and form building; these are not PDFGear mobile strengths and give PdfCraft a professional niche.
- Keep undo/recovery and schema-validated operations.

## Caveat

This comparison started from PDFGear’s publicly verified Play Store feature set and was then
corrected/supplemented with an on-device walkthrough of `com.pdfeditor.pdfeditorandriod` on the
`pdfcraft` AVD (home/file hub, viewer toolbar, View Settings, Edit mode, More menu: Print/OCR/
Convert/Share/Save as, etc.). The Play Store features and official description remain the source
of truth for capabilities not exercised hands-on.