# Delivery strategy: complete manual MVP, agent-ready by design

## Product decision

The first product MVP is a capable **manual PDF editor covering the full agreed manual feature
scope**. We are not cutting the editor down to a reader plus a few features. The work will still be
delivered feature-by-feature, with evidence at each step; a capability is not counted just because
an upstream crate or enum variant exists.

The agentic interface is explicitly later. The manual MVP should establish the deterministic
operation boundary that future local/cloud agents will use, but does not ship chat, a planner, model
weights, cloud processing, accounts, or billing.

## Fastest route with this product scope

“Fast” means reducing waiting and rework, **not deleting desired manual capabilities**:

1. M1's core open/render/navigation/Save As/reopen flow now passes on the emulator and is user-
   confirmed on a Galaxy S26 Ultra. Continue with password/error cases, provider cancellation and
   overwrite behavior, and lifecycle checks in M2.
2. Audit all desired operations against PdfCraft and classify support, mobile build blockers, tests,
   and dependencies. Lock the manual MVP acceptance checklist.
3. Add the narrow typed operation layer, then build the editor in independent vertical slices. Every
   slice goes from Flutter action → operation validation → existing PdfCraft API → save/reopen test.
4. Complete all manual capability groups: reading/search, annotation/drawing/text, page/document
   organization, forms/signatures, OCR/conversion/compression, and reliable save/recovery.
5. Validate the full checklist on Android and iOS before calling the cross-platform manual MVP done.
6. Use the operation registry for an optional agent after the manual feature suite is stable.

The schedule can be shortened by parallelizing **independent operation slices**, not by creating
separate PDF implementations or skipping save/reopen validation. Whether OCR, conversion, or editing
existing text is supported well enough is an audit result, not an assumption.

## Robustness gates shared by every route

- Document-provider open and Save As, cancellation/error handling, and verified reopen.
- Dirty/saved state, undo/redo and transaction semantics for edits; safe handling of destructive
  operations and unsaved work.
- Bounded work, renderer cancellation/staleness handling where possible, and documented large-file
  limits based on device measurements.
- Engine-backed tests for malformed PDFs, page bounds, passwords, each modifying operation, and
  resulting bytes.
- Android and iOS package/link/runtime tests before claiming cross-platform support.
- No model or network dependency for manual editing; no PDF-byte manipulation by an LLM.

Autosave and crash recovery should be part of the manual editor's save/recovery scope. Their exact
implementation may be staged, but loss of user work is not an acceptable tradeoff for shipping
faster.

## Agent-ready foundation (without agent implementation)

Build only the minimal reusable operation boundary alongside manual features:

- Stable operation ID and version; typed parameters and results.
- Input validation, active-document/page preconditions, and capability/security checks.
- Explicit read-only versus mutating behavior, undo/transaction semantics, and confirmation needs.
- Progress/cancellation support only for operations that can actually provide it.
- Structured, actionable errors and testable results.
- Manual controls call this layer; later agents receive only operations exposed by this registry.

Do not add generic plugin loading, a speculative JSON-RPC protocol, model-specific schemas, or an
autonomous execution loop now. Keep the operation definitions small and derive agent-facing
descriptions/schemas from them when that milestone begins.

## Platform sequencing

Android remains the engineering lead because the current host is Linux and the Android path is
buildable/testable here. iOS is still part of the product MVP, not a permanently deferred platform;
it requires a macOS/Xcode validation lane before cross-platform launch. Finish each engine-backed
operation once in shared Rust and expose it through Flutter on both systems rather than duplicating
PDF behavior in Kotlin and Swift.

The stage details and gates are in [`MILESTONES.md`](MILESTONES.md); verified implementation state is
in [`STATUS.md`](STATUS.md). Dates should wait until the operation audit and team capacity are known.
