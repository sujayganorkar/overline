# Touch-First UX Redesign & Interaction Flow Implementation

**Status:** IN PROGRESS  
**Reference Commit:** `adb28b52`  
**Focus:** Elimination of navigation overhead, unified action semantics, intent filtering, persistent editing sessions, and mathematical zoom physics.

---

## 1. Problem Matrix & Root Cause Analysis

### 1.1 Zoom Anchoring Defect (Page "Pinned in Bottom Right")
- **Root Cause:**
  1. `InteractiveViewer` was configured with `alignment: Alignment.center` while its child was wrapped in `SizedBox(width: constraints.maxWidth, height: constraints.maxHeight)`. In Flutter, `alignment` shifts the origin of `Transform` by `(width/2, height/2)`, compounding any matrix translation calculated assuming a `(0, 0)` origin.
  2. Double-tap and single-pointer zoom math used naive `..translate(-focal.dx, -focal.dy)..scale(s, s)` which pushes the focal coordinate off-axis into negative space, pinning the bottom-right corner to the screen.
- **Remediation:**
  - Remove `alignment: Alignment.center` from `InteractiveViewer`.
  - Maintain `constrained: true` with child `Center(child: SizedBox(width: pageWidth, height: pageHeight))`.
  - Use `TransformationController.toScene()` to calculate focal preservation:
    $$\Delta x = \text{focal}_x - \text{scene}_x \cdot S_{\text{target}}$$
    $$\Delta y = \text{focal}_y - \text{scene}_y \cdot S_{\text{target}}$$

---

### 1.2 Android Native Handoff (Missing `ACTION_VIEW` & `ACTION_SEND`)
- **Root Cause:** `AndroidManifest.xml` lacked `<intent-filter>` declarations for `application/pdf`, making the app invisible to "Open with..." or "Share to..." from WhatsApp, Gmail, or File Managers.
- **Remediation:**
  - Add `android.intent.action.VIEW` and `android.intent.action.SEND` for MIME type `application/pdf` in `AndroidManifest.xml`.
  - Extend `MainActivity.kt` with platform channel methods (`getInitialPdf` and `onNewIntent` streams) to pass incoming PDF URI content bytes to Flutter.
  - In `_ViewerPageState.initState()`, check for and auto-open received PDFs.

---

### 1.3 Ambiguous Persistence Semantics: "Apply" vs "Save PDF" vs "Share"
- **Root Cause:** In-sheet editing tools (`FormScreen`, `AnnotatePage`, `TextEditSheet`) displayed "Save" and "Form saved" when edits were merely applied to the in-memory engine session. Users believed their PDF was saved to disk, leading to accidental data loss.
- **Remediation:**
  - Standardize vocabulary:
    - **Apply**: Commits changes to the current working document in the engine session.
    - **Save PDF**: Persists the document bytes to local storage / file system.
    - **Share**: Exports and opens the system share sheet.
  - Change all in-sheet action buttons to `Apply` or `Apply changes` with clear snackbar copy: `"Form values applied to document"`.

---

### 1.4 Annotation Session Continuity
- **Root Cause:** `AnnotatePage._execute()` called `Navigator.pop(context, response.status)` after every single stroke or annotation, forcing a complete modal exit and re-entry cycle.
- **Remediation:**
  - Maintain the active annotation session in `AnnotatePage`.
  - Apply each annotation to the engine handle in-place, refresh the background render, clear the draft stroke, and display an accessible `"Annotation applied"` indicator.
  - Provide an explicit **Done** button in the AppBar to exit the session when the user chooses.

---

### 1.5 Signature-to-Share Flow
- **Root Cause:** Placing a signature in `SignaturePlacementPage` left the user on a blank canvas with no next action.
- **Remediation:**
  - Upon placement, render a sticky bottom **Completion Bar**:
    `[ Adjust ]` · `[ Add Date ]` · `[ Done ]` · `[ Done & Share PDF ]` (Primary FilledButton).

---

### 1.6 Typed Workflow Outcomes & Agent Bar Truthfulness
- **Root Cause:** `AgentCommandSheet` workflows returned generic void or ignored cancellation, unconditionally displaying `"Done — [task]."`
- **Remediation:**
  - Define `enum WorkflowResult { completed, cancelled, failed, needsInput }`.
  - Propagate `WorkflowResult` from sheets back to `_openAgentCommand()` and only celebrate when truly completed.

---

### 1.7 Session Correctness Fixes
- Clear text selection (`_textSelectionAnchor = null; _textSelectionExtent = null;`) upon page change in `_goto()`.
- Update `RecentDocumentsStore` cache with fresh bytes whenever `_save()` is performed.

