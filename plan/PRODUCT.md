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
- Build an optional offline assistant for request-to-tool mapping; it emits typed requests and never
  writes PDF bytes or receives unrestricted filesystem access.
- If cloud models are added later, make paid processing explicit, server-authorized, and opt-in.

## Manual editing is the first product MVP

The first product MVP is the **manual PDF editor**, with the full agreed manual capability set:

- Open, read, zoom, pan, navigate, search, and extract text.
- Highlight, annotate, draw with touch/stylus, insert text, and edit existing text where feasible.
- Fill forms and sign documents.
- Insert, delete, rotate, rearrange, merge, and split pages/documents.
- Compress, convert supported formats, and OCR scanned PDFs.
- Save, export/share, undo/recover, and preserve work reliably.

Deliver these in tested feature slices, but do not redefine the MVP as a reader plus only a few
editing tools. A capability counts as delivered only after auditing the real PdfCraft API,
validating mobile portability, and testing the complete operation through save/reopen. The list is a
product target, not a claim that every upstream crate already fulfills it.

The first MVP does **not** include the natural-language agent, local model runtime, or cloud AI.
Those follow the complete manual editor.

## Agent execution model

Manual UI actions and future models should converge on the same validated document-operation
handlers. Models select and parameterize operations; Rust/PdfCraft performs the deterministic work.
User confirmation, undo, transactions, and save policy belong to the application, not the model.
Design operation contracts before the first editing features; implement them incrementally as the
manual tools are built. Do not build a chat UI, agent loop, local model, or cloud service into the
manual MVP.

No agent, model runtime, billing, or cloud service belongs in the Android rendering proof of concept.
