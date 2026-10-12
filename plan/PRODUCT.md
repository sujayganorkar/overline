# Product principles

PdfCraft Mobile is an offline-first PDF manipulation environment with a touch-focused Flutter UI
and the upstream PdfCraft Rust engine. Conventional editing must remain useful without accounts,
network access, or AI. Android is the first validation platform; iOS shares the Flutter/Rust code
but is not considered supported until built and tested on macOS/Xcode.

## Product direction

- Keep the document as the central workspace; prefer discoverable, low-friction mobile controls.
- Preserve the user's source and work. Make save state clear, operations recoverable, and destructive
  actions explicit.
- Keep documents on-device by default. Do not upload files without a deliberate user action.
- Keep manual operations available independently of AI.
- Keep a touch-first Agent surface beside the conventional editor. Route known requests through
  reviewed workflows and the shared operation registry; do not let a model write PDF bytes or gain
  unrestricted filesystem access.
- If cloud models are added later, make paid processing explicit, server-authorized, and opt-in.

## Manual editing is the first product MVP

The first product MVP is the complete agreed **manual PDF editor plus the first reviewed task
workflows**, including:

- Open, read, zoom, pan, navigate, search, and extract text.
- Highlight, annotate, draw with touch/stylus, insert text, and edit existing text where feasible.
- Fill forms and sign documents.
- Insert, delete, rotate, rearrange, merge, and split pages/documents.
- Compress, convert supported formats, and OCR scanned PDFs.
- Save, export/share, undo/recover, and preserve work reliably.
- Target-size compression, document comparison with optional marked differences, and batch OCR when
  the offline OCR models are installed.
- A persistent Read / Edit / Organize / Agent structure. The Agent entry handles common workflows
  locally and falls back to searching the complete tool catalog.

Deliver these in tested feature slices, but do not redefine the MVP as a reader plus only a few
editing tools. A capability counts as delivered only after auditing the real PdfCraft API,
validating mobile portability, and testing the complete operation through save/reopen. The list is a
product target, not a claim that every upstream crate already fulfills it.

Known language starters route to the same manual flows; open-ended questions use on-device evidence
retrieval with page references. The current implementation is deterministic and extractive, not a
generative model. Evaluate an optional local model only after the reviewed task workflows are stable.
Cloud AI remains outside the MVP.

## Agent execution model

Manual UI actions and future models should converge on the same validated document-operation
handlers. Models select and parameterize operations; Rust/PdfCraft performs the deterministic work.
User confirmation, undo, transactions, and save policy belong to the application, not the model.
Design operation contracts before the first editing features; implement them incrementally as the
manual tools are built. Do not build a chat UI, agent loop, local model, or cloud service into the
manual MVP.

The first five agent hypotheses are: remove/review pages, reach a target size, find and mark
information, fill fields from user-provided details, and redact sensitive information. Each must
preview, ask before applying consequential edits, verify the result, and retain undo. No billing or
cloud service belongs in the offline-first MVP.

## Validation and privacy

For the first 100–200 beta users, propose opt-in, privacy-preserving measurement of feature launched,
task completed, touch vs. Agent entry, time-to-completion, undo/retry, and repeat use. Never collect
PDF contents, filenames, extracted text, or personal data. The ranking is a product hypothesis, not
a claim about private competitor usage.

Priority-2 cloud-oriented workflows (translation, automatic classification, financial extraction,
PDF/A repair, accessibility repair, and enterprise pipelines) remain deferred until demand supports
them.
