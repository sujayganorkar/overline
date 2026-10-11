# Decision 0002: complete manual editor is the first product MVP

- **Status:** accepted
- **Date:** 2026-10-12

## Context

The product vision includes a broad set of PDF editing capabilities plus natural-language agentic
editing. A narrow reader-only or small-feature MVP would prove the mobile stack but would not be the
intended first product. At the same time, implementing a model/planner before the document
operations are reliable would create two execution paths and force architectural rework.

## Decision

The first **product MVP** must cover the full agreed manual editing scope: reading/search, markup and
text tools, pages and documents, forms/signatures, OCR/conversion/compression, and dependable
save/undo/recovery. Deliver it in tested, auditable feature slices; do not claim capabilities until
the relevant PdfCraft API works through save/reopen on supported platforms.

Do not ship an agent, chat UI, local LLM, cloud processing, accounts, or billing in that MVP. While
building manual features, create a minimal typed operation registry/executor. Manual UI and future
agents must call the same validated operations, which dispatch to existing PdfCraft engine APIs.

## Consequences

- The Android viewer remains a technical M1 gate, not the product feature cut.
- M2–M5 establish document safety, reading, shared operations, and the full manual capability set.
- Android leads implementation; the product MVP is not called cross-platform until iOS builds and
  passes equivalent runtime checks on macOS/Xcode hardware.
- Operation definitions include validation, preconditions, mutation/undo semantics, confirmations,
  and structured errors. They are not a speculative plugin or model protocol.
- Local AI is considered only after manual operation behavior is stable; cloud AI is later still.
