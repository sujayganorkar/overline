#![deny(unsafe_code)]

#[allow(unsafe_code)]
mod frb_generated;

// PdfCraft mobile bridge: Flutter UI <-> PdfCraft Rust engine over flutter_rust_bridge.
//
// Phase 1 vertical slice: open a PDF, read page count + page size, render a page to PNG,
// save the working file. All PDF logic lives in the upstream engine crates (path deps into
// ~/src/pdfcraft); this crate is a thin adapter with no PDF logic of its own.

mod api;
pub use api::*;
