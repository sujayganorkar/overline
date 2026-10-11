# Architecture and boundaries

## Current proof-of-concept

```text
Flutter viewer + platform document picker
                  │ flutter_rust_bridge 2.13
                  ▼
       Rust Engine bridge handle
                  │ bounded async command channel (capacity 2)
                  ▼
   one worker thread owns PdfCraft Session
                  │
        pdfcraft-engine Session
          ├── open / inspect / save / close
          └── Document RenderPool → PNG bytes → Flutter Image
```

The `Engine` bridge object contains only a command sender and startup error. The `Session`, open
documents, and calls to PdfCraft are confined to the worker thread because the engine render pool
contains thread-local/non-`Sync` state. The command channel is bounded to prevent unbounded request
queues. Each request has a reply channel and a timeout. A timed-out open is discarded and closed
when parsing returns.

The mobile adapter uses PdfCraft's `Session::open`, `Session::get`, the `Document` page inspection
and `RenderPool`, `Session::save_bytes`, and `Session::close`. It does not implement PDF parsing,
rasterization, or writing. The current bridge returns a full-page PNG at a capped DPI for the
first viewer slice; it is not the planned tiled/high-zoom production renderer.

## Application responsibilities

- **Flutter**: document picker and Save As dialogs, viewer state, page navigation, loading/errors,
  and rendering the returned PNG. It passes selected bytes to the bridge and does not parse PDFs.
- **Rust adapter**: narrow typed API, worker ownership, bounded requests, timeouts, input range
  validation, and conversion to bridge-friendly values.
- **PdfCraft**: PDF parsing, inspection, rendering, editing, and serialization. Keep new PDF logic
  out of the adapter.
- **Document provider**: `file_picker` reads selected documents and writes Save As output using the
  platform picker. Do not assume `content:`/provider URIs are filesystem paths.

## Upstream source and build reproducibility

PdfCraft is a pinned Git submodule at `third_party/pdfcraft` (see `.gitmodules`). The mobile Cargo
workspace excludes that nested Cargo workspace and points at its engine crates using relative
paths. Its `hayro`, `hayro-interpret`, `hayro-syntax`, and `lopdf` crates are patched to the matching
upstream `vendor/` sources because the mobile build needs those not-yet-upstreamed changes. The
submodule commit, Cargo lockfile, and Flutter lockfile together define the tested dependency state.

Update PdfCraft by advancing the submodule pointer deliberately, then rerun host tests, Android
cross-compilation, APK packaging, and device checks. Do not follow upstream `main` implicitly.

## Known constraints and next architectural checks

- The current viewer reads the picked document into one Dart byte buffer before crossing FFI.
  Large-file memory copies and limits need measurement before production.
- The engine's `RenderPool` is reused; retain the pending request on each polling iteration per its
  queue contract. The bridge currently serializes operations per session.
- Rust `Session::close` and removal of the bridge handle release parsed document state. The widget
  closes its prior document after a new one opens and on disposal.
- Flutter Save As uses the system file picker. Test provider cancellation, overwrite behavior, and
  reopen of returned URIs on real Android and iOS devices before relying on it for production saves.
- iOS has only a generated project skeleton until Rust static-library packaging and Xcode linking
  are verified on macOS.
- Before distribution, audit the licenses/notices for PdfCraft, the submodule's vendored crates,
  all transitive native/runtime dependencies, and any shipped models/assets; include required notices
  in the app packages.
- Current PNG handoff is a proof path. Profile render latency, memory, and repeated navigation on
  devices before deciding between the engine pool, tiles, or another pixel transport.

## Agent-ready operation boundary

The current bridge methods (`open`, `page_count`, `render_page_png`, `save`, `close`) are proof-of-
integration API calls, not yet the complete editor operation architecture. Before broad editing,
introduce a small typed operation registry/executor and route manual UI actions through it. This is
part of building the manual editor, not an agent runtime.

Each real operation should describe:

- Stable operation ID/version, typed arguments, and typed result.
- Input validation and document/page/security preconditions.
- Read-only versus mutating behavior; dirty-state and undo/transaction handling.
- Destructive-action confirmation requirements and structured, actionable errors.
- Progress/cancellation only when the underlying operation supports it.

The executor dispatches to existing `pdfcraft-engine` APIs; no new PDF logic belongs in the adapter.
Manual buttons call the same operation handlers future agents will call. Later, expose operation
descriptions/schemas to a constrained planner. Do not add chat/model code, arbitrary JSON-to-PDF
calls, filesystem access for models, a generic plugin system, or autonomous execution during the
manual MVP.
