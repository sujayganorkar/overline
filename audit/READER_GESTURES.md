# Long press and zoom inspection

## Long-press behavior

- Single-page reader: long press selects a line; dragging extends the line selection. The selection dock provides copy, highlight, underline and strikethrough. Selection starts within a bounded screen-space tolerance near text, rather than a tolerance that becomes much larger when magnified.
- Continuous or facing-page reader: long press offers “Select text” for the touched page. Accepting explicitly switches to single-page view and selects using that page's text. This prevents a right-hand page gesture from operating on the first page's text. The continuous-page hit surface fills its viewport even while the image is decoding.
- Text editor: its inline platform text field supplies native caret, word selection and copy/paste behavior.
- Annotation editor: long-press line selection is available in Select text mode. Other tools retain their drawing/placement behavior.
- Page grid: long press enters page selection for batch operations.
- A multi-touch sequence stays interrupted after one finger lifts, so the remainder cannot create a reader selection.

Reader selection remains line-based. Word-level selection directly on the rendered reader PDF is not implemented by this change.

## Zoom and navigation fixes

- The document subtree observes the transformation controller, so gesture policy and selection handle sizes react to both pinch and button zoom.
- Continuous pages scroll at fit scale. Once zoomed, page scrolling pauses and one-finger dragging pans the magnified PDF. Reset restores page scrolling.
- Single-page fit view does not pan into a blank margin. Zoom remains available through pinch, double tap and the zoom controls.
- Facing-page navigation requires the same deliberate horizontal swipe threshold as single-page navigation. Taps and vertical drags no longer turn spreads.
- The facing spread's combined bounds are used for double-tap focal positioning and canvas height.
- New pointer interactions and zoom-control commands stop a running double-tap animation. Page and reading-mode changes also stop it.
- Selection handles compensate for magnification across the full 1×–8× range and retain a 48-screen-pixel target.
- Reader controls and selection actions stay in the dock outside the PDF canvas.

## Validation

24 targeted Flutter tests passed, including continuous zoom/pan/scroll switching in both directions, fit/reset policy, facing-page swipe validation, right-hand page selection, pinch interruption, animation interruption, 8× selection handle size, control touch targets and existing annotation touch behavior. Analysis of the changed gesture files is clean. The Android release was built for ARM64 and x86_64. No physical-device usability test was performed.
