# Text editor implementation and validation

The editor now uses a full-page route with inline paragraph input, rather than a replacement dialog. Existing paragraph editing and new page-text placement share the same editing session.

## Delivered behavior

- Editor entry obtains the current page render independently of reading-mode caches. Vertical and horizontal continuous reading now open the editor.
- Editable paragraph outlines and a text-block list provide two ways to select text. Nearby ambiguous targets get a chooser. Hit tolerance is measured in screen pixels and accounts for zoom.
- Selecting a paragraph places the text input on the page and reveals it above the keyboard. Native platform caret, selection, copy/paste and IME interaction stay available inside that input.
- Font family, size, bold, color and alignment controls are available. Blocks have move and width handles, plus button alternatives for horizontal movement and width adjustments.
- Add text places a draft where the user taps. The existing annotation “Add text to page” entry now opens this editor at that location. Fill & Sign remains a separate signing operation.
- Draft previews use a fresh document copy from the session baseline. Preview failure retains the text; preview copies close on success, failure and after the editor is dismissed.
- Preview generations prevent a delayed result from replacing a more recent draft.
- **Review PDF** shows the actual native-engine render. Apply is enabled only after the current preview has painted. A stale image cannot enable Apply.
- Apply checks that the source page's text/geometry and render still match the baseline, then submits the reviewed operation once. A successful edit notifies the reader before refreshing the editor. The editor stays open for further work.
- A failed commit retains the reviewed draft for retry. Dismissal is blocked during commit. Changed drafts require a discard decision; unchanged selections do not create an edit or undo step.
- Undo restores the last edit made in this editor. Applying text does not mark the PDF saved to storage.
- Candidate paragraph bounds are checked for possible page overflow or overlap with existing paragraphs. These are warnings for review, not a complete collision solver.

## Fidelity boundaries

This is **on-page draft editing with an authoritative PDF review step**. The live caret/input uses platform fonts and approximate input layout. It does not yet reproduce arbitrary embedded/subset font metrics at every caret position. The real font, wrapping and positioning are visible in Review PDF before Apply.

Formatting is applied to a whole paragraph. Partial rich-text styling within a paragraph and PDF-glyph-accurate word/caret hit testing remain future engine/UI work. Engine paragraph replacement can normalize whitespace and line breaks; the PDF review shows the actual outcome.

Snapshot copies of password-protected PDFs may require a password that is not available to the preview session. Such a preview will fail with the draft retained and Apply disabled; this path still needs encrypted-document coverage. Complex scripts, font fallback, long blocks, rotation and device-specific IME behavior require a broader PDF/device matrix.

Draft safety covers this editing session. Process-death recovery of an unapplied draft is not implemented. No physical-device usability study was performed.

## Validation

- **13 editor/entry regression tests passed:** preview isolation and cleanup, source-conflict rejection, one-time apply, no-op selection, failed preview/commit recovery, discard handling, blocked dismissal during commit, stale preview rejection, narrow keyboard layouts, new text placement, pinch protection, undo, and entry from both continuous modes.
- **4 native smoke tests passed.** The new real-engine test verifies that a candidate and its committed operation produce identical PNG bytes, previewing does not dirty the source, one Undo restores the original render, and save/reopen preserves that restored result.
- Phone input/review layouts were visually inspected using PNGs produced by the native engine. Apply now waits for the reviewed image to paint.
- Full Flutter suite: **100 passed, 1 unrelated existing failure** in `cloud_agent_and_billing_test.dart` (“renders Overline Pro features and buttons”). It taps a trial button outside the visible viewport. That test imports only billing/agent/paywall code and was not changed here.
- Analysis of changed production and regression-test files is clean.

The audit-only characterization harnesses remain under `audit/` as historical reproductions. Current regression coverage is in `test/text_edit_test.dart` and `test/text_edit_entry_test.dart`; the native render equivalence test is in `rust/tests/smoke.rs`.
