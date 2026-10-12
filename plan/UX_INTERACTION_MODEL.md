# Interaction model — PdfCraft Mobile

Design authority for how every engine capability is served in the app. Status:
**implementation in progress**. The viewer, four-surface navigation, operation
catalog, touch annotation, forms, signatures/date placement, page grid,
organization/export/security sheets, recipes, and local command routing exist;
see `STATUS.md` for what has actually been verified.

## 1. Principles

1. **The page canvas is home.** Reading, drawing, placing, and selecting happen
   directly on the rendered page. Everything else is a transient layer over it.
2. **Direct manipulation over dialogs-about-things (direct-manipulation).**
   Prefer acting on the object itself — draw the stroke, drag the box, tap the
   placement point — and reserve typed forms for what cannot be pointed at
   (names, passwords, ranges).
3. **Reachability first (thumb zone, Fitts).** Primary and destructive-safe
   actions live in the bottom half; destructive confirmations require an
   explicit second tap, never sit under the thumb's rest position, and never
   use swipe-to-delete without undo.
4. **Recognition over recall.** Tool names, plain-language descriptions, and
   search stay visible (hub lists + palette search). No memorized gestures
   beyond draw/tap/drag/pinch; every mode announces itself in the title.
5. **Error prevention and forgiveness.** Destructive tools confirm (registry
   `destructive` flag drives this); every mutation is undoable through the
   engine; dirty state is always visible; unsaved work blocks careless
   navigation with a choice, never silent loss.
6. **Visibility of system status.** Busy indicators on the triggering control,
   a persistent status line, and explicit save outcomes (“Saved to …”,
   “Save cancelled”, never a silent no-op).
7. **Progressive disclosure.** Hubs show the common path first and reveal
   advanced arguments on demand; the palette holds the long tail so the main
   UI never becomes a 144-item menu.
8. **Consistency across surfaces.** The same operation ID run from a gesture,
   a sheet, the palette, or (later) an agent produces the same validated
   result — one execution path, many affordances.
9. **Accessible by default.** 48dp minimum targets, semantic labels on every
   icon button, dynamic text support, and errors as text (never color alone).
10. **Three entry surfaces, no more.** Canvas gestures for direct acts,
    hub sheets for feature families, command palette as the guaranteed
    fallback for everything. No fourth way to do the same thing.
11. **Coordinates are one system.** All geometry is top-left-origin points;
    `pt = px × 72 / dpi` (`annotation_geometry.dart`). Every canvas mode
    reuses it, so a tap means the same place in every tool.
12. **No dead ends.** Every sheet handles empty states, errors stay on screen
    as text, and long operations show progress with the engine timeout as
    the backstop.

## 2. App structure

```text
Viewer (canvas)
├── App bar: Undo · Redo · Save · Share · Open
├── Persistent canvas command: Ask (thumb-reachable floating action)
├── Bottom bar: page prev/next, status (dirty • recovery saved), page count
└── Four thumb-reachable surfaces
    ├── Read: find · bookmarks · comments · summary/evidence
    ├── Edit: draw · highlight · text · forms · sign/date · pages
    ├── Organize: create/merge/split · export/compress · protect/redact
    └── Agent: natural-language starters → reviewed recipes, else tool search
```

The page canvas remains home. Surface buttons reveal small task lists instead
of putting 20 operations on the screen. The floating Ask action remains
available over the canvas. Save, Share, Open, Undo, and Redo stay in the app
bar; page position and recovery state remain visible at the bottom.

## 3. Canvas gesture map

| Gesture (mode) | Tool call | Args source |
|---|---|---|
| Draw stroke (Draw) | `comment_add` ink | strokes, color, width |
| Drag box (Rect/Oval) | `comment_add` rectangle/oval | rect from drag corners |
| Drag line (Line/Arrow) | `comment_add` line/arrow | from/to |
| Tap (Note) | `comment_add` note | at + contents dialog |
| Tap (Sign place) | `fill_sign_add` signature | at + name dialog |
| Tap (Text place) | `fill_sign_add` text | at + text dialog |
| Drag box (Link) | `link_add` | rect + URL dialog |
| Drag box (Redact) | `redact_mark` | rect |
| Tap points (Measure) | `measure_distance/perimeter/area` | accumulated points |
| Long-press + drag (Select, phase 2) | `comment_add` highlight/underline/strikeout | quads from `text_lines` glyph boxes |
| Tap comment marker (phase 2) | open comment thread | `comment_list` rects hit-test |

Pinch-zoom and pan always stay available (InteractiveViewer); annotate
routes lock to drawing gestures only while open.

## 4. Hub-by-hub tool coverage

Notation: **Bespoke** = dedicated UI (built or planned); **Palette** = reachable
in Tools browser today; **Phase 2** = needs extra work (noted).

### 4.1 Read hub (viewer + dialogs)

| Tool(s) | Treatment |
|---|---|
| `page_render`, `render_preview` | Viewer canvas (built) |
| `text_find` | Find bar with next/prev + match count (Phase 2; palette today) |
| `text_extract` | Share/export-text sheet with page range (Phase 2; palette today) |
| `text_lines`, `text_paragraphs` | Powers text selection (Phase 2; palette today) |
| `bookmark_*` (6) | Bookmarks screen: tree, tap-to-go, add/rename/move/delete (Phase 2) |
| `link_list`, `links_from_urls`, `link_add/edit/delete`, `links_remove` | Links screen + canvas drag-to-add (Phase 2; palette today) |
| `doc_info`, `doc_inspect`, `doc_revisions`, `doc_open_revision` | Document screen: metadata, security, revision list + open (Phase 2; palette today) |
| `doc_audit_space` | Document screen section (Phase 2; palette today) |

### 4.2 Annotate hub (built: overlay + highlight dialog)

| Tool(s) | Treatment |
|---|---|
| `comment_add` ink/line/arrow/rectangle/oval/note | Annotate overlay (built, verified) |
| `comment_add` highlight/underline/strikeout/squiggly via `find` | Highlight phrase dialog (built, verified) |
| `comment_add` textbox/typewriter/caret/callout | Annotate overlay text mode (Phase 2: tap → keyboard → place) |
| `comment_add` stamp/stamp_custom | Stamp picker sheet with `at` tap-place (Phase 2) |
| `comment_add` attachment | File picker → `stage_file` → attach at tap point (Phase 2) |
| `comment_add` replace | Phrase dialog with replacement text (Phase 2) |
| `comment_add` polygon/cloud/polyline | Multi-tap canvas mode (Phase 2) |
| `comment_list/reply/set_status/mark/lock/edit/delete`, `comments_hide/summarize` | Comments screen: thread list → actions (Phase 2; palette today) |
| `comment_image_preview` | Signature/image placement preview (powers drawn-signature flow, Phase 2) |

### 4.3 Pages hub (built: grid + actions; extend per below)

| Tool(s) | Treatment |
|---|---|
| `page_move/delete/duplicate/rotate/insert_blank` | Grid actions (built, verified) |
| `page_insert_file`, `page_replace`, `page_extract` | Grid overflow + file picker + Save As for outputs (Phase 2) |
| `page_set_box` (crop) | Crop mode: drag box on canvas → margins/rect (Phase 2) |
| `page_number` (labels) | Labels sheet: range + style + prefix (Phase 2) |
| `doc_header_footer/watermark/background/remove_marks` | Marks sheet: text/color/placement form (Phase 2) |
| `doc_combine`, `doc_create_multiple`, `doc_split` | Organize screen: multi-file picker → run → Save As outputs (Phase 2) |

### 4.4 Forms & Sign hub (built: fill screen + typed signature)

| Tool(s) | Treatment |
|---|---|
| `form_fields`, `form_fill`, `form_reset` | Fill form screen (built, verified) |
| `form_add_field`, `form_delete_field`, `form_set_props`, `form_set_image`, `form_tab_order` | Field authoring: tap-to-place rect + type picker; image via picker (Phase 2) |
| `form_detect_fields` | One-tap “Detect fields” with confirm (Phase 2) |
| `form_actions`, `form_set_actions`, `form_set_script` | Advanced field screen (palette; Phase 3) |
| `form_merge_data`, `doc_export_data`, `doc_import_data` | Import/export sheets with file pickers (Phase 2) |
| `fill_sign_add` text/check/cross/dot/line/date | Quick-mark sheet: tap-to-place + text/date (extends built signature flow; Phase 2) |
| `fill_sign_add` signature/initials (typed) | Signature sheet (built, verified) |
| `fill_sign_add` signature via image | Drawn-signature pad → PNG → `stage_file` → place (Phase 2) |
| `sign_id_create`, `sign_document`, `sign_list`, `sign_trust` | Digital-ID screen: create .p12 in workspace, sign to output, validation list (Phase 2; desktop-only ID stores stay hidden on mobile) |
| `comment_image_preview` + `comment_edit` | Drawn/image signature placement & commit (Phase 2) |

### 4.5 Redact & Secure hub

| Tool(s) | Treatment |
|---|---|
| `redact_mark` (rect/find/pattern) | Redact mode: drag box or phrase/pattern form → marks (Phase 2) |
| `redact_apply`, `redact_clear` | Confirm-gated actions (destructive flags already confirm in palette) |
| `doc_remove_hidden` (sanitize categories), `doc_hidden_info` | Sanitize checklist sheet → run → report (Phase 2) |
| `doc_protect`, `doc_unprotect` | Password/permissions sheet (Phase 2) |
| `doc_flatten` (comments/fields) | Confirm-gated action (Phase 2) |

### 4.6 Measure hub

| Tool(s) | Treatment |
|---|---|
| `measure_distance/perimeter/area` | Canvas tap-points mode with live label (Phase 2) |
| `measure_scale`, `measure_snap`, `measure_info` | Scale setup sheet; snap assists canvas (Phase 2) |
| `measure_list`, `measure_export` | Measurements screen + CSV Save As (Phase 2) |

### 4.7 Content & text editing hub

| Tool(s) | Treatment |
|---|---|
| `page_add_text`, `page_add_image` | Tap-to-place text/image with style form (Phase 2) |
| `text_edit` (line/paragraph) | Tap-a-paragraph → edit sheet (uses `text_paragraphs` boxes; Phase 2) |
| `object_list`, `object_move` | Select-objects mode → drag (Phase 2) |
| `content_list/update/delete`, `image_edit`, `image_save`, `page_images` | Added-content manager screen (Phase 2) |

### 4.8 Export, print, compare, OCR, optimize

| Tool(s) | Treatment |
|---|---|
| `doc_export_images/text/office/all_images`, `doc_export_data`, `measure_export`, `comments_summarize` | Export sheet: format picker → run → Save As outputs (Phase 2) |
| `doc_print`, `printers`, `printer_options` | Android share sheet → system print (no desktop spooler UI; Phase 2) |
| `doc_compare`, `doc_compare_report`, `doc_compare_mark` | Compare screen: pick other file → summary + optional mark (Phase 2) |
| `ocr_recognize`, `ocr_recognize_files`, `ocr_status` | OCR screen: status → recognize with progress → report (needs model-download flow; Phase 2) |
| `doc_optimize`, `doc_reduce` | Compress sheet: target/quality presets → Save As (Phase 2) |
| `pdfa_convert`, `pdfa_verify` | Standards row with level picker (Phase 2) |
| `doc_set_info`, `doc_initial_view` | Document settings screen (Phase 2) |
| `js_run`, `js_document_scripts`, `js_set_document_script`, `js_enabled`, `fill_sign_date_format`, `accessibility_*`, `action_list/run`, `command_*`, `page_enhance_camera`, `object_*` extras | Palette only (Phase 3 / on demand) |

### 4.9 Deliberately palette-only (no bespoke UI planned)

Desktop-only identity stores (`sign_windows_ids`, `sign_keychain_ids`), raw
scripting (`js_run`, `js_set_document_script`), command meta-tools, and other
power-user tools stay in the command palette with their schemas. They are
served — just not with custom screens.

## 5. Build order (next implementation slices)

1. **Comments screen** (list/reply/status/edit/delete) — completes Annotate.
   Implemented and verified on the Android emulator, including thread display,
   nested replies, status chips, and a fixed tap-placement path.
2. **Bookmarks screen** — completes Read alongside a find bar.
3. **Page overflow actions** (extract/replace/insert-file/crop/labels/marks) — completes Pages.
4. **Quick-mark + drawn-signature pad** — completes Sign; field authoring completes Forms.
5. **Redact mode + sanitize/protect sheets** — completes Secure.
6. **Organize + Export sheets** (combine/split/extract/exports) — completes file ops.
7. **Measure mode, content/text editing, OCR screen, compare, compress** — in usage order.
8. **Text selection with glyph quads** — upgrades highlight from phrase to selection.

Each slice: UI → same `execute_tool` entries → host test where logic lives
in Dart → emulator verification with screenshots → docs update.

## 6. Why the agent becomes quick work after this

Every row above is already a stable tool ID with a JSON schema, validation,
and structured results in the registry the app calls. An agent needs only:
tool discovery (`operation_catalog`), argument construction (the same schemas
the sheets render), and confirmation policy (the `destructive` flag). No new
PDF execution path is required — manual and agent actions will literally call
the same function.

## 7. Touch grammar — how a human holds the phone and what each touch means

Written for the implementer: for each feature family, the human intent, the
exact touch sequence, what the finger sees mid-gesture, and what makes the
action safe. A phone is held one-handed (thumb, ~44pt precision, screen as
small as 360dp wide) or two-handed (stylus/finger precision). Primary flows
must survive the thumb; precision flows may assume two hands.

### 7.1 Reading and navigating (the 90% case)

The human is reclined, one thumb free, and wants the next page with zero
thought. The page always opens fit-to-width — the whole page visible, never a
cropped corner of an oversized render. At fit scale, a deliberate swipe turns
the page in either axis (left for next, right for previous, up for next, down
for previous); once pinched past ~1x, the same drag pans instead of turning,
so zoom never traps the reader. Tap does nothing on the page (no accidental
triggers — a deliberate choice). Page turns stay redundant and
thumb-reachable: swipe, bottom prev/next chevrons, a tappable page counter
with a validated Go-to-page dialog, tap-a-thumbnail in Pages,
bookmark/comment jump. Pinch zoom is always live and never trapped by modes —
annotate routes own their gestures only while open, and closing them restores
the plain viewer. Find sits as an overlay bar (not a screen) so context is
never lost; matches are counted (“2 of 5”) and stepping jumps pages.
Rotation and backgrounding must never lose the page: viewer state is plain
integers, re-rendered on return, with the transform reset on every page
change.

### 7.2 Selecting text (the fat-finger problem)

A fingertip covers ~10 glyphs, so raw glyph-tapping is dishonest UI. The
honest ladder, cheapest first: (1) name the phrase in a dialog (built —
`find` does the locating, the human only recalls words); (2) drag a box that
snaps to whole lines (built Select mode — the drag is approximate, the snap
is exact, and the yellow wash previews exactly what will be marked before
Save); (3) future: word-level handles for surgical selection. Never let the
preview lie: the wash shows snapped lines, and Save marks exactly those.

### 7.3 Drawing and shapes (direct manipulation)

The human points at the thing they mean: circle this, arrow to that,
scribble here. One stroke equals one annotation — multi-stroke ink
accumulates into a single annotation until Save, matching the mental model
of “one drawing”. Style (color, width) is chosen before touching the page,
per the recognition-over-recall rule; changing it later edits the saved
comment, not the draft. Undo removes the last stroke, never the whole
drawing. Live preview uses a contrasting wash; the engine render after Save
is the source of truth, and any mismatch is treated as a bug, not a
rendering difference.

### 7.4 Notes and threads (conversation model)

A note is tap → type → save; a thread is list → reply → resolve. The loop
between seeing and discussing must be closed on the canvas itself: comment
markers drawn from `comment_list` rects sit on the page, and tapping one
opens its thread — without this, comments are write-only and the feature is
undead. Author identity defaults to the engine default; remembering a
user-chosen display name is a small, explicit future (never silently reuse
personal data). Status/mark/lock are triage gestures on the thread card, each
one tap with immediate visual change (chip, checkmark, lock icon).

### 7.5 Forms (data-entry model)

Nobody taps a 12pt PDF checkbox with a thumb and expects success. So the
form screen lists every field as a full-width native control — the list IS
the touch target strategy. Text gets keyboards, checkboxes get tiles,
radios/combos get pickers, read-only values are shown, not offered.
Authoring inverts this: the human picks a type, then a preset band
(top/middle/bottom), because typing point rects on glass is absurd. Field
detection (`form_detect_fields`) is one button, since the engine does the
looking. Every fill is one undo step and shows dirty state immediately.

### 7.6 Signing (ceremony model)

Signing is a ritual, not a setting: choose the kind (type/draw), preview
exactly where it lands on the real page, commit with an explicit Place
button, then consciously save — the app must never auto-persist a signature
or drop it at a blind default. Typed is a name field → tap-to-preview →
Place; drawn is a finger pad → transparent PNG → the same tap-to-preview →
Place flow; both offer one-tap Undo after placement. There are no numeric
coordinate fields anywhere in the ritual. Digital ID remains legal weight
(.p12 picker, sign-to-output, palette/advanced). The placed mark stays
editable (movable annotation) until flattened or saved.

### 7.7 Pages (spatial model)

Humans think of pages as cards on a table: the grid shows live thumbnails
(one engine render each, cached per grid session), the current page is
badged, tap goes there. Selection is a separate, explicit mode entered by
long-press: tap adds pages, a fixed bottom bar shows Extract/Delete with
counts, and delete confirms by naming the pages (never all of them) with
Undo after. Reorder is its own mode with drag handles AND large up/down
arrows per row — arrows are the honest control on small screens, drag is the
fast one; every move reports its position with Undo. Extract lives in the
selection bar (no typed page ranges). Insert (blank/file), duplicate,
replace, crop, labels, and marks live one level down from the grid so the
spatial metaphor never breaks.

### 7.8 Redact and secure (consequence model)

Redaction is the highest-consequence action in the app, so mark and apply
are deliberately different verbs on different screens: marking paints a red
wash (reversible, visible, undoable); applying requires an explicit confirm
and says “permanently” out loud. Passwords ask for open vs permissions
passwords in plain words, never jargon. Sanitize lists what dies (metadata,
scripts, layers…) before running. Flatten warns that comments/fields become
paint. Nothing here runs on a single thoughtless tap.

### 7.9 Measure (instrument model)

Like a tape measure: tap points on the thing, see the polyline grow with a
live point count, choose the instrument first (distance/perimeter/area), save
to bake the annotation. Calibration (`measure_scale`) and export stay one
level down until carpenters actually ask. Points snap visually (markers);
true geometric snap (`measure_snap`) is a documented upgrade.

### 7.10 Organize and export (file model)

Humans think in files, not byte streams: combine picks files (order shown
before running — picker order is not trustworthy, so a future pass adds
reorder), split/extract name their outputs, and every produced file ends in
the system Save As sheet — nothing ever lands silently in an invisible
workspace folder. Long runs show progress state; cancellation is honest
(engine timeout) rather than fake.

### 7.11 Undo everywhere (safety-net model)

Undo/redo live in the app bar with the engine's own labels (“Undo Rotate
page”), enabled exactly when `can_undo`/`can_redo` say so. Every mutating
surface refreshes them from the returned status. There is no dead edit: if
it changed the document, it can be un-changed, up to save.

### 7.12 Empty, error, and offline states

Every hub states what is missing and which action creates it (“No comments
yet — Draw or Highlight to add some”). Engine errors render as text where
the action was invoked, with the tap-to-retry being simply tapping again.
Offline is the default assumption: everything except model download works
without connectivity, and missing OCR models report status instead of
crashing.

## 8. Abundance leverage — underused tools and their zero-cost surfaces

The catalog is larger than any toolbar. Tools below need no new screens —
only a row, a confirm, or an automatic offer in an existing surface:

| Tool(s) | Surface (no new screen) |
|---|---|
| `links_from_urls` | “Make links clickable” row in Export sheet |
| `form_detect_fields` | Button atop the Fill form screen |
| `comments_summarize` | Button in Comments app bar → Save As |
| `bookmark_from_structure` | Button in Bookmarks app bar |
| `doc_compare_mark` | “Mark differences” after Compare in Export sheet |
| `measure_export` | Row wherever measure results show |
| `doc_audit_space`, `doc_inspect` | Rows in a future Document info screen (palette today) |
| `accessibility_check` | Guided row in Export sheet (palette today; full fix-flow later) |
| `ocr_recognize_files` | Multi-pick extension of the OCR row (needs staged multi-file loop) |
| `stamp_custom`, attachment/callout/polygon modes | Annotate mode chips reusing tap/drag plumbing |
| `comment_image_preview` | Powers drawn-signature drag-to-place (future) |
| `js_*`, `*_ids` desktop stores, meta commands | Palette only, deliberately |
| Printing | Android share sheet → system print (no spooler UI ever) |

## 9. Implemented touch flows for the research-priority work

These flows extend the grammar above and should be kept as interaction
contracts, not reduced to schema forms:

| Task | Touch sequence and safety contract |
|---|---|
| Share current PDF | One app-bar tap snapshots the current edited bytes into the native share sheet. Sharing does not mark the open document saved; canceling leaves its dirty state intact. |
| Autosave/recovery | Every edit schedules a short-debounce checkpoint in app-private storage. Backgrounding forces a checkpoint. On restart, the user chooses Restore or Discard; a recovered file remains visibly unsaved until Save As. |
| Delete several pages | Long-press a thumbnail to enter selection; tap more thumbnails; a fixed bottom bar shows the count with Extract/Delete. Delete opens a second confirmation naming the selected pages, blocks deleting every page, then leaves normal Undo available. |
| Reorder pages | Reorder mode → drag handles or large up/down arrows per row → each move reports its new position with Undo. No typed position numbers. |
| Photos to PDF | Pick photos → inspect page order → drag or use large up/down buttons → Create PDF → system Save As. The file is created without requiring a PDF to be open. |
| Place a date | Sign & date → choose a page → tap once to preview the engine-formatted date → inspect/retap → explicit Place button → short Undo action. |
| Place a signature | Type a name or draw with a finger → tap the page to preview at real scale → inspect/retap → explicit Place button → short Undo action. No blind default corners, no coordinate fields. |
| Highlight a phrase | Type words → search first → review match count, pages, and text snippets → confirm → highlights applied per page with multi-step Undo. “Every match” and “every page” are separate, explicit choices. |
| Compress to size | Enter an MB target; progressively optimize to measured quality/resolution profiles; review Original vs Compressed page previews with size/percentage before deciding; the open source stays unchanged; Save As is explicit. |
| Compare and mark | Pick the older file → read the comparison report → separately confirm marking differences. Marks are comments on the current PDF and remain undoable. |
| Highlight dates | Extract date candidates → show them as selectable values with occurrence/page previews → apply selected highlights; each mark uses the shared `comment_add` tool. |
| Redact phones | Confirm reversible marks → inspect the page → open Secure → explicitly confirm permanent Apply. Phone text is not removed by the find step. |
| Fill from provided details | Paste `Field label: value` lines → exact normalized-label matches only → review/check values → inspect/edit the full-width form fields → Save. Unknown labels are not guessed. |
| Summaries and questions | Extractive summary or lexical evidence search returns source sentences with page numbers; tapping a result jumps to that page. It does not invent unsupported answers or send document text off-device. |
| Batch OCR | Select PDFs → check local model availability → run a per-file batch → offer every successful searchable copy via Save As and show per-file errors. |

Agent requests route known starters to these same reviewed screens. Unknown
requests are declined in plain words — never executed as hidden engine
operations. The current router is deterministic and offline; a future model
may improve language coverage but must preserve the same
preview/apply/verify/undo contract.

Nothing in the user interface shows serialized engine payloads: no JSON, no
schema text, no workspace paths, no content URIs. Results are summarized in
plain words (`result_summary.dart`), counts and page references are shown
where they matter, and every produced file is delivered through the system
Save sheet. The advanced operation browser from earlier prototypes is removed
from the UI for this reason.
