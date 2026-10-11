# Decision 0001: pin PdfCraft as a Git submodule

- **Status:** accepted for the mobile proof of concept
- **Date:** 2026-10-12

## Context

The engine is an active multi-crate Cargo workspace. Its member crates inherit version, edition,
and lint metadata from the upstream workspace and the render path depends on modified `hayro` and
`lopdf` crates under upstream `vendor/`. Absolute sibling paths build locally but fail for another
developer or CI checkout. A plain Cargo git dependency does not directly express this combined
workspace-local patch arrangement.

## Decision

Pin upstream as a Git submodule at `third_party/pdfcraft`. Use relative path dependencies to the
engine crates and relative `[patch.crates-io]` entries to the submodule's vendored crates. Exclude
the nested upstream workspace from the mobile workspace. Clone with submodules initialized.

## Consequences

- The exact source revision is visible in the mobile repository's gitlink.
- Upstream license/attribution files remain with upstream source; product distributions must retain
  required notices for linked and bundled dependencies.
- Developers and CI must initialize submodules.
- Updating upstream is an explicit pointer change plus compatibility validation.
- Cargo.lock records resolved registry dependencies; Flutter `pubspec.lock` is committed as an app
  lockfile.

This choice is accepted only after `cargo test` and Android cross-build succeed from the submodule
layout. It may be revisited if upstream later publishes a mobile-ready, independently consumable
engine crate with stable registry releases.
