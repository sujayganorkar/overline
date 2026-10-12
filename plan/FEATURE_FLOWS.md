# Feature flows — PdfCraft Mobile (as built)

Traced from the moment the user taps the app icon. Every step below is what
the code does today (`lib/`, `rust/src/api.rs`), not what is planned.
Tags: **[seen]** = observed on the x86_64 API-35 emulator this session;
**[code]** = read in source, not yet exercised on device.

Interaction reference checked against current iPhone Preview documentation:
[Annotate a PDF or image in Preview](https://support.apple.com/guide/iphone/annotate-a-pdf-or-image-iph73ca5c8e6/26/ios)
and [Get started with Preview](https://support.apple.com/guide/iphone/get-started-with-preview-on-iphone-iph7239ea3b5/ios).
Preview’s documented text-marking contract is **touch-and-hold a word → adjust
selection grab points → choose Highlight/Underline/Strike → choose color**;
its Markup tools separately add notes, text, shapes, and signatures, with Undo.

## 0. Launch

1. Tap app icon → `main()` runs `PdfCraftApp` → `ViewerPage`. No splash,
   no file list, no tabs. **[seen]**
2. Engine starts: first-party channel `getSupportDir` → `RustLib.init()` →
   `Engine(workspace)` on a worker thread. Title row shows “Starting engine”
   then “Engine ready (PdfCraft Rust core)”. **[seen]**
3. Recovery check: if app-private `recovery/recovery.pdf` exists, a blocking
   dialog offers **Restore / Discard / Keep for later**. Restore opens the
   bytes as “Recovered - \<name\>”, flagged unsaved. **[code]**
4. Empty home (no document): status text + three buttons — **Open a PDF**
   (filled), **Create PDF from photos** (outline), **Combine PDF files**
   (text). The bottom nav bar is hidden until a document is open. **[seen]**

## 1. Opening a document

1. **Open a PDF** (home) or folder icon (app bar) → system file picker,
   PDFs only. **[seen]**
2. Bytes are read and `engine.open(name, bytes)` stages them into the
   app workspace. If the open fails with a password error, a password
   dialog appears and open is retried once with the entered password.
   Anything else → “Open failed: …” in the status line. **[code]**
3. Page count + status load, viewer renders page 1 at 96 dpi, title becomes
   “\<name\> - N pages”. The previously open document (if any) is closed
   only after the new one opens. **[seen]**
4. If the current document is dirty, opening/replacing first asks
   **Save / Discard / Cancel**; Save runs the full Save flow, Discard
   closes with `discardChanges: true`. **[code]**

## 2. Viewer chrome (a document is open)

- App bar: **Undo** (engine label, e.g. “Undo Move page”), **Redo**,
  **Save**, **Share**, **Open**. Undo/redo disable at stack ends. **[seen]**
- Page canvas: full page fit to viewport. One-finger swipe (any direction,
  past a ~56px threshold) turns pages **only at fit scale**; pinched past
  ~1x the same drag pans via `InteractiveViewer` (max 8x). Pinch zooms
  freely. Page turns reset zoom. Tap does nothing. **[seen both axes]**
- Comment markers: 48px touch targets drawn over the page at engine rects;
  tap opens Comments. **[seen]**
- **Ask** floating button (bottom-right, above nav): opens the Agent
  command sheet. **[seen]**
- Bottom nav: **Read / Edit / Organize / Agent**. Tapping one highlights
  it and opens a scrollable action sheet (3–6 rows); tapping a row runs
  the flow. Agent goes straight to the command sheet. **[seen]**
- Status row: status text (“Swipe to turn pages · Pinch to zoom” after
  render, “Unsaved · recovery saved” when a checkpoint exists) + prev /
  tappable “N / M” counter / next. The counter opens a **Go to page**
  dialog with range-validated input (“Enter a page from 1 to M”). **[seen]**

## 3. Read surface

Sheet rows: Find in PDF · Bookmarks · Comments · Summary & evidence ·
Links (destination list, tap jumps, confirmed delete). **[seen: added
link listed with URL + page]**

Viewer text selection (no surface needed): touch-and-hold a word → drag
across lines → snapped yellow preview with start/end handles → pick
Highlight/Underline/Strike → pick a color for highlights → **Apply** (one
undoable edit) or **Copy selected text** (clipboard) or ✕ to dismiss.
Line-granular, honest about precision. **[seen: “2 lines selected” →
“Marked 2 selected lines”, “Selected text copied.”]**

- **Find in PDF** (`find_bar.dart`): overlay bar under the title (viewer
  stays visible). Type → Search runs `text_find` (limit 200). Label shows
  “i of N” (`+` when the engine reports more); up/down step through matches
  and jump pages; first search auto-jumps to the first match. **[code]**
- **Bookmarks** (`bookmarks_screen.dart`): full screen, tree list with
  indent, “Page N / No destination”. Tap jumps and closes. `⋮` per node:
  Rename / Point at current page / Delete (confirmed). App bar: **+**
  (bookmark current page), build-from-headings, refresh. Empty state
  explains the + button. **[code]**
- **Add a comment/note**: Read → Comments → app-bar **+** (or the empty
  state’s **Add a note**) → the actual page opens in Note mode → tap the
  location → type the note → **Add note**. `comment_add` creates the PDF
  note annotation immediately, returns to Comments, and reloads the list.
  The viewer shows a tappable note marker; tapping it opens Comments filtered
  to that page and scrolls/highlights the corresponding thread. This creates
  a sticky note, not a reply to an existing thread. **[seen on API-35
  emulator: note count updated to 1; tapping the marker opened “Comments ·
  page 1 (1)” with its text and reply/status actions]**
- **Comments** (`comments_screen.dart`): full screen, “Comments (N)” (or
  “Comments · page N (M)”), refresh + “Summarize to PDF” (writes
  `outputs/comments-summary.pdf`, offered through Save As). Thread cards show
  type · page, author, date, text, status chip, replies; actions: reply, set
  status, mark, lock, edit, delete (delete confirmed). Tapping a card header
  jumps to its page. **[code]**
- **Summary & evidence** (`document_insights_sheet.dart`): exports text,
  then two offline actions — **Find evidence** (keyword overlap over
  sentences, top 8 with page numbers) and **Summarize** (frequency-scored
  extractive top 5 in reading order). Tapping a result jumps to its page
  and closes. Copy states it returns source sentences, not generated
  claims. **[code]**

## 4. Edit surface

Sheet rows (demand order): Draw & annotate · Select text to mark · Find
a phrase to highlight · Sign & date · Fill form · Pages · Edit existing
text. Annotate toolbar is grouped (Draw/Mark/Note/Text/Shape/Measure/More)
with Line/Arrow/Rect/Oval and Page-text/Stamp/Picture/Redact/Link variant
strips; stamps and pictures place by tap; measurements report their value.
**[seen: Rect via Shape strip; APPROVED stamp in render; picture placed]**

- **Draw & annotate** (`annotate_page.dart`): full-screen page with a
  grouped toolbar — Draw, Mark, Note, Text, Shape (variant strip:
  Line/Arrow/Rect/Oval), Measure, More (Page text, Redact, Link) — plus
  style (color/width) controls. Redesigned 2026-10-12 from a 12-chip
  scroll row; verified (Shape → Rect → drag → Save → “Undo Add
  rectangle”, red rect in render). Draw
  accumulates strokes into one annotation until Save; Note taps to place
  then types; Redact drags a box into `redact_mark`; Measure taps points
  with a live count then saves; Select touch-holds a word, drags through
  text, snaps to line boxes, shows yellow line previews and adjustable
  start/end handles, then applies via the bottom toolbar; Link drags a box
  then asks for a URL. Save
  applies and returns fresh status to the viewer (re-render); close without
  saving discards the draft. **[code; ink/highlight/note verified earlier]**
- **Select text to mark** (Edit → this row or Annotate → Select):
  touch-and-hold text → drag across lines → review the snapped yellow lines
  and start/end handles → choose Highlight/Underline/Strike → Apply. This
  is line-granular; it does not pretend to offer word-level precision.
  This follows Preview’s selection-first sequence but currently snaps to whole
  text lines rather than exposing word-level grab points. **[code; rebuilt
  APK test pending]**
- **Find a phrase** (`main.dart`): dialog with phrase field,
  “Highlight every match” (default on), “Search every page” (default off,
  = current page only). **Find matches** runs a real `text_find` first
  (paginated past 500, hard stop past 5,000 with “narrow the phrase”),
  then a preview dialog shows count, page list, and up to 4 text snippets
  with **Cancel / Highlight N**. Apply runs one `comment_add` per page;
  snackbar reports the result with multi-step **Undo**. **[seen live:
  “1 match found… Highlight 1” → marker → “Undid 1 change”]**
- **Fill form** (`form_screen.dart`): lists every field as a full-width
  native control (text → keyboard, checkbox → tile, radio/combo/list →
  picker; read-only shown, signature/button rows redirect to tools).
  App bar: Detect fields (one tap), Save. Card on top: **Use details to
  fill fields** — paste `Label: value` lines → exact normalized-label
  matches only → checkbox review → values land in the fields unsaved for
  inspection before Save. FAB: **Add field** (type, page, top/middle/
  bottom band, optional name). **[code]**
- **Sign & date**: chooser sheet — saved typed/drawn signature first
  (when one exists: “Use … / Saved on this device — tap to place” goes
  straight to placement), else Type / Draw / Place today’s date / Add a
  checkmark or mark (check ✓, cross ✕, dot ●, line ― via the same
  tap-preview page). Typing or drawing remembers the signature in
  app-private storage for next time. **[seen: typed once and placed;
  reopened chooser offers “Use …” and jumps to placement]**
  - Type → name field → **Choose placement** → full-page preview where
    the typed name renders at tap point → **Place signature** → snackbar
    with Undo. **[code]**
  - Draw → finger pad (Clear / Continue to placement) → PNG staged with
    transparency → same tap-preview → Place → Undo. **[code]**
  - Date (`quick_mark_page.dart`) → shows today in the engine’s date
    format → tap page to preview → **Place date here** → Undo.
    Page chevrons inside. **[code]**
- **Edit existing text** (`text_edit_sheet.dart`): full page with
  paragraph boxes from `text_paragraphs`; tap near a line selects the
  nearest paragraph (42pt tolerance, else “tap near a line of text”),
  highlight previews the box; **Edit selected text** opens the rewrite
  dialog (shows font/size); Replace runs `text_edit`; **Browse text
  blocks** lists paragraphs as fallback. **[code]**
- **Pages** (`page_grid.dart`): thumbnail grid, current-page badge, hint
  line (“Tap to open · long-press to select · More …”). Tap opens;
  long-press starts multi-select (tap toggles, check badges). Bottom bar
  in select mode: Cancel · Select all · **Extract N** (new PDF via Save
  As) · **Delete N** (names pages, blocks deleting all, Undo after).
  Header: **Reorder** mode (drag handles + up/down arrows per row, each
  move reports position with Undo, Done exits), **Insert** (blank page at
  the end, or pages from another PDF after the current page).
  Per-page **More**: rotate ±90°, duplicate, delete (confirmed),
  (move-to-position removed in favor of Reorder). **[seen: reorder move
  → “Undo Move page” → redo; select/delete covered by widget test]**

## 5. Organize surface

Sheet rows: Create, combine & split · Export & compress · Protect & redact.

- **Create, combine & split** (`organize_sheet.dart`, grouped
  Create/Pages/Stamp; also reachable with no document, showing only the
  file rows):
  - Combine PDFs: pick other PDFs → **order sheet with the open PDF
    already first** (“The open PDF is already first…”, current version
    with your edits via a released snapshot) → drag/arrows → Combine →
    Save As. Needs 2+ total inputs, else “Choose at least one more PDF”.
    Fixed 2026-10-12: the open document used to be excluded, so picking
    one file errored confusingly. Verified: open form-test + combine-b →
    Save dialog → combined file. **[seen]**
  - Create PDF from photos: pick images → same order sheet (“each image
    becomes one page”) → `doc_create_multiple` → Save As. **[code;
    engine path covered by Rust smoke test with a real PNG]**
  - Split document: Every-N-pages or Max-MB dialog → outputs → Save As
    each. **[code]**
  - Extract pages: row opens the Pages grid (long-press/tap selection →
    Extract N → Save As); the row subtitle still says “Copy a range…” —
    stale copy, see §9.
  - Number pages: from/to/style (1/i/I/a/A)/prefix → `page_number`.
    **[code]**
  - Header & footer: separate header + footer fields with `<<1>>`/`<<n>>`
    token hint → `doc_header_footer`. Watermark: text + opacity slider +
    behind switch. Background: five preset tints. Remove
    headers/watermarks row via `doc_remove_marks`. **[seen: yellow tint
    applied with “Undo Add background”; header dialog renders, args
    host-tested]**
- **New blank PDF**: empty-home **Start a blank PDF** or Organize →
  **New blank PDF** → page count (1–100, validated) → Save As. The bridge
  writes the bytes to a file and never opens a hidden document.
  **[seen: blank.pdf saved, reopened as 13 pages]**
- **Export & compress** (`export_sheet.dart`):
  - Export text → `doc_export_text` → Save As `.txt`. **[code]**
  - Export pages as images → this page/all as PNG/JPEG → each image
    offered through Save As. **[seen: page-1 PNG saved, 22 KB]**
  - Convert to Word/format → chooser (.docx/.html/.rtf) →
    `doc_export_office` → Save As. **[code]**
  - Recognize text (OCR): checks `ocr_status`; if models missing the
    dialog says so and offers only Close (nothing runs); else Recognize
    → humanized word/page summary. **[code]**
  - OCR multiple PDFs: pick PDFs → model check → confirm (“originals
    stay unchanged”) → per-file staging with progress → successful copies
    each offered via Save As → per-file errors shown together. **[code]**
  - Compare with another PDF: picker titled “Choose the older PDF
    version” → summary report in plain words → separate **Mark these
    differences?** confirm (open doc = newer) → marks land as undoable
    comments. **[code; `doc_compare_mark` covered by Rust test]**
  - Compress: Balanced (`doc_optimize` 150ppi) / Reduce (Acrobat preset)
    → Save As; or **Try to reach a file size…** → MB target (validated,
    early-out if already below) → tries six quality/ppi profiles,
    measuring each → visual review dialog (Original/Compressed toggle,
    page navigation, actual size + % smaller) → Keep original / Save
    compressed copy → Save As. **[code]**
  - Verify PDF/A → plain-words result dialog. **[code]**
- **Protect & redact** (`secure_sheet.dart`):
  - Mark text for redaction (phrase; every match is marked — there is no
    per-match toggle because the engine marks all matches). Fixed
    2026-10-12: the dialog used to send an `all` argument the engine
    rejects, so marking always failed and Apply could never succeed.
    Verified after fix: “fill” marked and applied, render shows
    “Please █ in this form.”, undo restores it. **[seen]**
  - Apply redactions: confirm (“removed for good… checks that marked text
    is no longer readable”) → apply → sheet closes so the page is
    visible → “Review the page, then Save”. **[code]**
  - Clear redaction marks; Remove hidden information (confirmed);
    Protect with passwords (open vs permissions in plain words);
    Remove security (confirmed); Flatten comments & fields (confirmed).
    Every row reports a named outcome, never “Done”. **[code]**

## 6. Agent surface

- **Ask** FAB or Agent tab → `AgentCommandSheet`: “Choose a task in your
  own words. PdfCraft will show the next step before making a change.”
  Text field + 7 chips (Highlight every date, Redact phone numbers,
  Compress below 2 MB, Compare another PDF, Review pages to remove,
  Summarize this PDF, Make this PDF searchable). **[seen]**
- Known requests route to the reviewed screens (recipes with dates/phones
  pre-started, export for compress/compare/OCR, pages, forms, highlight,
  secure, sign, insights for questions/summaries). **Unknown requests show
  “That task is not available yet” with the list of supported tasks —
  nothing executes.** No model, no network, no catalog fallback. **[seen
  sheet; routing covered by widget test]**
- **Guided recipes** (`recipes_sheet.dart`): Review-and-remove pages
  (hands off to Pages grid), Highlight dates (detect → checkbox review
  with occurrence counts → apply with Undo-all), Find-and-redact phones
  (confirm → reversible marks → Review button hands to Secure for the
  permanent Apply), plus shortcuts to target-size and compare. **[code]**

## 7. Cross-cutting flows

- **Save** (app bar): snapshot → system Save As → user picks location →
  commit (dirty cleared, recovery checkpoint deleted) or cancel (snapshot
  released, “Save cancelled”, dirty kept). Concurrent-edit guard: if the
  doc changed mid-dialog, commit is refused with “save the latest version
  again”. **[code; Save As round-trip seen in earlier sessions]**
- **Share** (app bar): snapshots current bytes (dirty or clean) into the
  native share sheet as `<name>.pdf`. Never marks saved; cancel keeps
  dirty state. **[code]**
- **Undo/redo** (app bar): engine labels (“Undo Add highlight”);
  multi-step helpers undo N edits for batch applies. Every mutating
  surface refreshes labels + dirty + page count and re-renders. **[seen]**
- **Autosave/recovery**: edits schedule a 700ms-debounced checkpoint to
  app-private storage (atomic tmp→rename + metadata); backgrounding
  forces one; checkpoints are skipped while a save/share is in flight.
  Title shows “Unsaved · recovery saved” once written. Restart offers
  Restore/Discard/Keep. **[seen “recovery saved” + restore path in code]**

## 8. What this document does NOT claim

- OCR flows need downloadable models that are not installed; only the
  missing-model path is exercisable today.
- No encrypted-PDF fixture test; password retry is code-only.
- iOS: unbuilt. Physical-device pass of the newest flows: pending.
- Annotate modes beyond ink/note/highlight and the FormScreen prefill are
  code-only (emulator time went to viewer/pages/highlight/agent).

## 9. Redesign candidates spotted while tracing (for next pass)

1. Organize “Extract pages” subtitle (“Copy a range…”) describes a
   removed typed-range dialog; it now opens visual selection.
2. Organize marks (header/watermark/background) offer text only — no
   font/size/color/placement; header row is footer-only despite its name.
3. Split dialog is typed numbers only; could reuse visual page selection.
4. Agent sheet has no visible history of what was just done; after a
   routed task the user lands in a sheet with no back-link to the request.
5. Status line mixes hint text (“Swipe to turn…”) with operation results;
   first-run hint vs. ongoing status deserve separate slots.
6. Empty Comments/Bookmarks states are text-only; no direct
   create-buttons inline (Bookmarks has + in bar; Comments has none).
