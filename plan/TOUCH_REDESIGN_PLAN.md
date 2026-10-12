# Touch redesign — full audit and build plan

Agents skipped per product decision. Goal: every engine capability reachable
through honest touch UI, each flow optimized for one-handed phone use.
Status key: ✅ verified on device · 🧪 engine/host-tested · 📝 code-only ·
❌ missing · 🔧 to rebuild.

## A. Audit by surface

### Viewer chrome
| Item | State | Decision |
|---|---|---|
| Fit page, swipe both axes, pinch pan, reset on turn | ✅ | Keep |
| Gesture hint shares the status line | 🔧 | One-time coach snackbar on first open; status shows op results only |
| Go-to-page dialog | ✅ | Keep |
| Ask FAB overlaps selection bar | ✅ fixed | Keep hidden while selecting |
| App bar undo/redo/save/share/open | ✅ | Keep |

### Read sheet (Find, Bookmarks, Comments, Summary) — keep all; +1 row
| Item | State | Decision |
|---|---|---|
| Find bar overlay | ✅ | Keep |
| Bookmarks tree + add/headings | 📝 | Keep |
| Comments + add-note + markers | ✅ | Keep |
| Summary & evidence | 📝 | Keep |
| Links list/go/delete | ❌ (`link_list/edit/delete` exist) | **NEW Links screen** |

### Edit sheet — reorder by demand + keep all rows
New order: Draw & annotate, Select text to mark, Highlight text, Sign &
date, Fill form, Pages, Edit existing text. (Pages was below the fold.)

### Annotate toolbar (just regrouped) — extend tap modes
| Item | State | Decision |
|---|---|---|
| Clusters + variant strips | ✅ | Keep |
| Stamp placement | ❌ (names known) | **NEW tap mode**: tap → standard stamp picker → place |
| Image on page | ❌ (`page_add_image` staged-file ready) | **NEW tap mode**: tap → image picker → stage → place |
| Measure value feedback | 🔧 | Show measured value in snackbar after save |

### Pages grid — keep; +2 selection actions
| Item | State | Decision |
|---|---|---|
| Select/extract/delete/reorder/insert/rotate/dup/more | ✅ | Keep |
| Replace selected pages with file | ❌ (`page_replace` exists) | **NEW selection-bar action** |
| Crop single page by drag box | ❌ (`page_set_box` rect, single page) | **NEW Crop page** from More menu |

### Organize sheet — section headers + honest marks dialogs
| Item | State | Decision |
|---|---|---|
| Combine/photos/blank/split | ✅ | Keep; fix Extract subtitle (“Copy a range” → visual select) |
| Header&footer row writes footer-only | 🔧 | Real dialog: header + footer fields, token hint, start page |
| Watermark text-only | 🔧 | Add opacity slider + behind switch (engine-supported) |
| Background text-only | 🔧 | Preset color chips (engine takes color) |
| Remove header/footer/watermark | ❌ (`doc_remove_marks` exists) | **NEW row** with kind picker |
| Split typed dialog | Keep | Numbers are the honest UI here; clarify labels only |

### Export sheet — section headers + two rows
| Item | State | Decision |
|---|---|---|
| Text/office/images/OCR/batch/compare/compress/PDF-A | ✅/🧪 | Keep; group Convert / Improve / Review |
| Compare report Save As | ❌ (`doc_compare_report` exists) | **NEW**: bridge passes path through; Save button in compare flow |
| Measurements CSV export | ❌ (`measure_export` exists) | **NEW row** (export only; no list screen) |

### Secure sheet — section headers only (Redact / Clean / Lock)

### Sign chooser — section headers (Saved / Create new / Place marks-date)

### Forms — +3 small actions
| Item | State | Decision |
|---|---|---|
| Fill/prefill/detect/author | ✅ | Keep |
| Reset to defaults | ❌ (`form_reset` exists) | **NEW app-bar action**, confirmed |
| Export/import values | ❌ (`doc_export_data`, `doc_import_data`, `form_merge_data`) | **NEW menu**: export → Save As; import → picker → run |

### Recipes + Agent sheet — keep; agent gets a done-snackbar back-link
After a routed flow returns, show “Done — \<task\>” so the request isn’t
orphaned. No other agent work.

### Deliberately out (documented, not missing)
Desktop spooler print (share covers it), metadata edit, initial view,
JS tools, OCR models (blocked upstream), scan-to-PDF (needs camera
plugin — next hardware-dependent slice), dark mode (renders stay white),
word-level grab points (engine lines only), recipes for finance/PDF-A.

## B. Build list (this pass) — all built; device/host evidence below
1. Rust: `doc_compare_report` through `compare_with_file` (path
   passthrough) + allowlist. ✅ host-tested (report is a valid PDF)
2. main: Edit demand order, one-time coach snackbar, neutral Ready
   status, agent done-snackbar. ✅ seen (coach + Ready on device)
3. Organize: Create/Pages/Stamp sections, real header+footer dialog,
   watermark opacity/behind, background presets, extract subtitle fix,
   remove-marks row. ✅ seen (sections render; yellow tint applied with
   “Undo Add background”, no spurious Save dialog)
4. Export: Convert/Improve/Review sections, compare-report save choice,
   measurements export with empty-state guard. ✅ code + host-tested
5. Secure + Sign chooser: Redact/Clean/Lock and Saved/Create/Marks
   sections. ✅ seen
6. Forms: reset (confirmed), export values (CSV/XFDF → Save As), import
   values (picker → review → Save). ✅ code + host-tested
   (`form_reset`)
7. Annotate: stamp + image tap modes, measure value in snackbar.
   ✅ seen (APPROVED stamp in render; image placed, “Undo Add image”)
8. Crop page screen + PageGrid More entry. ✅ seen (region kept,
   “Page cropped.” + Undo)
9. Links screen + Read entry. ✅ seen (added link listed with
   destination, jump + delete present)
10. PageGrid selection bar: Replace action. ✅ code + host-tested
    (`page_replace`)
11. Host tests: page_replace, compare_report, measure_export,
    form_reset, doc_remove_marks, stamp place, page_add_image,
    header/footer+watermark options, insert_file, check mark, image
    export. ✅ all green
12. Device-verified: stamp, crop, image, background tint, links add/list,
    Edit order, sections, coach. Dialog-Apply taps under automation
    keyboard focus stay flaky; header/footer Apply is dialog-rendered +
    host-tested (same `_run` pattern as verified rows).

## C. Acceptance per item
Same contract as before: touch → preview → explicit commit → undo;
no JSON/paths/URIs on screen; analyzer + tests green; device proof for
the new touch paths; docs updated.

## D. Bugs found by this audit (fixed)
1. Annotate `_execute` ignored its `tool` argument and always called
   `comment_add` — Redact-box, Link, Page-text, and Picture modes were
   all broken. Fixed + verified (stamp, link, image placed on device).
2. Mutating tools echo the open document's staging path
   (`imports/mobile-N-….pdf`) inside their summary, and the shared output
   saver offered it for Save As — serving the **pre-edit original** as if
   it were a result (caught on Background tint). Fixed two ways:
   Organize only scans file-producing calls (`collectOutputs`), and the
   saver refuses `imports/` segments and absolute paths. Regression test:
   `test/output_saver_test.dart`.
