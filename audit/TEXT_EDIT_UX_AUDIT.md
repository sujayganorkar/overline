# Text editing UX audit — Overline

> Historical audit of the implementation before the rework. See [implementation and validation](TEXT_EDIT_IMPLEMENTATION.md) for the current behavior. The reproduction harnesses below characterize that earlier implementation and are not current acceptance tests.

Date: 23 October 2026. Scope: existing paragraph edits, adding page text, touch targeting, draft safety, rendering, completion and undo. Production code was not changed for this audit.

## Verdict

**The current implementation does not meet the touch-first WYSIWYG requirement.** It is a paragraph-replacement dialog launched from a static PDF preview. It provides no on-page caret, draft layout rendering, or pre-commit review of the actual replacement. Reliability fixes are needed before expanding the interaction model.

This is a code and automated-widget audit, not a physical-device usability study. “Smooth” and “intuitive” still need validation with people on phones. Native font fidelity, complex-script shaping and overflow need a representative PDF corpus; the existing native smoke test is not sufficient evidence for those requirements.

## Confirmed findings

### 1. P1 — The dialog controller can be disposed while the dialog is still exiting

[TextEditSheet._edit](/home/sujay/Downloads/pdfcraft-mobile/lib/widgets/text_edit_sheet.dart:189) pops the dialog, awaits the result, and disposes its controller in `finally` at line 248. A popped route can still be animating and rebuilding its text field.

**Observed:** the audit widget run produced `A TextEditingController was used after being disposed` on Cancel, immediate failure and immediate success paths. This is a reproducible debug assertion; a release-device crash has not been established.

**Fix:** give the composer its own state and controller lifetime. Dispose when that widget is removed, not when the caller receives the dialog result. Cover keyboard/IME activity during dismissal.

### 2. P1 — Failed saves and dismissal lose the draft

At [lines 212–230](/home/sujay/Downloads/pdfcraft-mobile/lib/widgets/text_edit_sheet.dart:212), Replace closes the editor before `text_edit` succeeds. Failure shows a notice with no retained draft or retry action. Reopening constructs a new controller from the original paragraph. Cancel, barrier dismissal and Back do not check for modified text.

**Evidence:** code-confirmed. Attempts to exercise the full recovery flow also encountered finding 1, so these must not be described as clean end-to-end passing tests.

**Fix:** keep the draft visible through validation and engine failures. Offer Retry without retyping. Ask before discarding a changed draft; allow unchanged drafts to close immediately. Disable Apply when nothing changed.

### 3. P1 — Closing during a mutation can leave reader state stale

The [Close control](/home/sujay/Downloads/pdfcraft-mobile/lib/widgets/text_edit_sheet.dart:269) stays enabled while `_busy` is true; the host bottom sheet is also dismissible. After the engine operation finishes, [line 231](/home/sujay/Downloads/pdfcraft-mobile/lib/widgets/text_edit_sheet.dart:231) returns if the sheet has unmounted, skipping `onStatusChanged`.

**Impact:** an edit can succeed in the document while the parent misses the refresh, dirty-state update and undo availability. This does not prove the document bytes were lost; it proves the UI notification is conditional on the editor still existing.

**Fix:** have a document/session owner deliver mutation results independently of the composer lifecycle. Either prevent exit during commit or explicitly finish it after dismissal. Never silently abandon completion handling.

### 4. P1 — Edit text silently does nothing in continuous reading modes

[Continuous rendering](/home/sujay/Downloads/pdfcraft-mobile/lib/main.dart:625) clears `_png`, while [_openTextEdit](/home/sujay/Downloads/pdfcraft-mobile/lib/main.dart:2947) requires `_png` and returns silently if it is null. Both vertical and horizontal scrolling take this path. Two widget reproductions confirmed that selecting the tool closes the tool picker and opens no editor.

**Fix:** acquire the current page image as part of opening the editor, independently of the reader's image cache. Show loading or an actionable error. The same command must work in single, facing, vertical and horizontal views.

### 5. P1 requirement gap — What the user types is not what the PDF previews

The [text field](/home/sujay/Downloads/pdfcraft-mobile/lib/widgets/text_edit_sheet.dart:196) uses the app's default typography. The source font and size are only helper text. The [page image](/home/sujay/Downloads/pdfcraft-mobile/lib/widgets/text_edit_sheet.dart:308) remains the original PNG. No draft rendering occurs while typing; applying the edit closes the entire sheet.

**Observed:** the typing characterization test confirms the field is inside an AlertDialog, has no explicit PDF text style, and makes no draft-render calls.

**Fix:** make the page the editing surface. A responsive input overlay alone is not sufficient for exact WYSIWYG: use the PDF engine to render the candidate layout before Apply, with that render as the authority for the final result. Keep the selected block visible above the keyboard and remain in the editing session after applying.

### 6. P2 — Layout and font changes are not explained before commit

The engine has capabilities that the mobile UI does not expose: block width, movement, alignment, font, size, color and spacing. The UI submits only page, paragraph and text, and ignores response content describing the resulting font.

Relevant native behavior:

- [Whitespace normalization](/home/sujay/Downloads/pdfcraft-mobile/third_party/pdfcraft/crates/edit/src/text.rs:1256) collapses ordinary separators into spaces; explicit line breaks typed into the multiline field are not a promise of matching PDF line breaks.
- [Default width](/home/sujay/Downloads/pdfcraft-mobile/third_party/pdfcraft/crates/edit/src/text.rs:1287) allows a single-line block to grow toward the page margin rather than retaining only the highlighted original width.
- [Font fallback](/home/sujay/Downloads/pdfcraft-mobile/third_party/pdfcraft/crates/edit/src/text.rs:1336) can substitute a font. The automation response exposes the resulting paragraph font, but the mobile editor does not inspect it.
- The rewrite wraps and emits additional lines; the inspected path does not provide the mobile UI with a collision/overflow review.

**Status:** source-confirmed behaviors and missing safeguards; exact visual effects on complex PDFs were not measured in this audit.

**Fix:** show actual candidate bounds and font substitutions. Define a consistent overflow policy: resize the box, change formatting, or reject with an explanation. Do not silently claim that a generic multiline field preserves PDF layout.

### 7. P2 — Touch selection lacks a precise editing contract

[Hit testing](/home/sujay/Downloads/pdfcraft-mobile/lib/widgets/text_edit_sheet.dart:122) selects the nearest paragraph within 42 PDF points. That tolerance scales visually with zoom; it is not a constant finger-sized target. Equal-distance/overlapping blocks are resolved by enumeration order. Only the selected block is outlined. There is no on-page caret, word-level selection, magnifier, or resize/move handles in this editor. The fallback block list is useful but selecting a list item does not reveal that block at a comfortable zoom.

**Fix:** exact block hit first, bounded screen-space tolerance second, explicit disambiguation for nearby blocks. In Edit mode, make editable areas discoverable. Selecting a block should reveal it and enter a predictable caret/selection state. Preserve pinch/pan behavior and test against accidental edits after multi-touch.

### 8. P2 — Adding text is a separate, inconsistent interaction

[Add page text](/home/sujay/Downloads/pdfcraft-mobile/lib/widgets/annotate_page.dart:591) opens another dialog and submits a fixed 12-point size. [Fill & Sign text](/home/sujay/Downloads/pdfcraft-mobile/lib/widgets/annotate_page.dart:552) uses a separate operation. Neither path previews the typed text at its page location before placement. These are different PDF object types and should not be presented as interchangeable editing behavior.

**Fix:** one visible Text mode with clearly named “Edit existing text” and “Add text” actions. Place and adjust a draft on-page before committing; preserve distinctions for form filling without forcing users to understand engine tool names.

## Recommended interaction contract

1. Enter **Edit text** on the current page. Show editable blocks and a clear exit; keep navigation reachable without covering the page.
2. Tap a block to select it. Tap within it to place the caret; long-press selects a word. A selected block can be moved/resized through handles, not accidental page drags.
3. Keep the selected area visible when the keyboard opens. A compact formatting bar belongs above the keyboard. Pinch zoom must not create edits or change the selection unexpectedly.
4. Keep a local draft. Render candidate changes on an isolated document snapshot with the real PDF engine. Discard stale preview responses; do not accumulate mutations on the user's document as they type.
5. Show the latest candidate layout, font substitution and overflow feedback. Do not enable Apply against a stale or failed preview. Character-level caret placement and partial formatting will need a richer text-layout contract than the mobile Paragraph model currently provides.
6. Apply one document operation with one undo step. Stay on the page with the result selected and Undo available. Distinguish applying an edit from saving the PDF to storage.
7. Done exits the session. Back first handles selection/draft state. Failed saves preserve text, selection and view position.

## Implementation order

- **First:** controller lifetime, draft preservation, commit/dismissal handling, and entry from every reading mode.
- **Second:** an on-page editor and engine-rendered candidate preview. Agree on supported block/character formatting and overflow semantics before adding controls.
- **Third:** touch refinement, accessibility, multilingual/complex-document coverage and user testing.

## Acceptance gates

- No draft disappears on engine error, keyboard dismissal, route transitions or rotation. No unchanged edit creates an undo step.
- Every reading mode opens the same editor on the selected page. Editing multiple blocks does not require reopening the tool each time.
- Preview and committed render use the same layout path. Font substitution and overflow are visible before Apply.
- Touch controls offer at least 48 logical pixels where feasible; test at 320–430 px widths, enlarged system text, zoom extremes and keyboard-open layouts.
- Pinch, pan, caret movement, selection-handle drag and block resizing have distinct outcomes with no unintended mutation.
- Validate save/reopen and undo/redo on actual PDFs: multi-column text, rotated/cropped pages, embedded/subset fonts, mixed styles, images behind text, ligatures, unsupported glyphs, CJK, RTL and Indic scripts. Test scanned pages with an actionable OCR path.
- On Android hardware, test Gboard composition, predictive replacement, paste, emoji/unsupported characters, screen-reader labels, and interrupted commits. Measure typing responsiveness and preview latency; no latency claim is supported yet.

## Reproduction and validation

Audit-only harnesses are deliberately outside the normal `test/` directory. They characterize current defects and should not be mistaken for acceptance tests or a claim that the UX passes.

```sh
flutter test --no-pub audit/text_edit_audit_test.dart --reporter expanded
flutter test --no-pub audit/text_edit_entry_audit_test.dart --reporter expanded
cargo test --offline -p pdfcraft-mobile-api --test smoke manual_operation_catalog_edit_undo_save_reopen -- --exact
```

The editor characterization run: **1 test passed, 4 failed**, with controller-disposal and follow-on framework assertions. The passed test establishes absence of live PDF preview, not WYSIWYG compliance. The native smoke test passed; it demonstrates basic bridge edit/search/save/reopen behavior, not typography equivalence or touch usability. Both reading-mode characterization tests passed, reproducing the silent entry failure. Audit-only analysis is clean. Full-project analysis reported six existing warnings/info findings outside the audit files (agent provider, billing service, page grid, paywall and agent tests); those unrelated files were not modified.

No production implementation changes or APK build were made for this audit.
