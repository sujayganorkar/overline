// End-to-end smoke test of the bridge against the real engine: the engine's own
// `create_from_text` produces a PDF, which the adapter opens, inspects, renders to PNG,
// saves, and re-opens.

use pdfcraft_mobile_api::Engine;

fn png_dimensions(png: &[u8]) -> (u32, u32) {
    assert!(png.starts_with(&[0x89, b'P', b'N', b'G']), "not a PNG");
    assert_eq!(&png[12..16], b"IHDR", "missing IHDR");
    let w = u32::from_be_bytes([png[16], png[17], png[18], png[19]]);
    let h = u32::from_be_bytes([png[20], png[21], png[22], png[23]]);
    (w, h)
}

#[tokio::test]
async fn open_render_save_roundtrip() {
    let source = pdfcraft_engine::Session::new()
        .create_from_text("hello", "Hello PdfCraft Mobile")
        .expect("engine could not create a test PDF");
    assert!(source.len() > 500, "engine produced a suspiciously small PDF: {} bytes", source.len());

    let engine = Engine::new();

    // Open: page count comes from the engine's inspection.
    let doc = engine.open("hello.pdf".to_owned(), source.to_vec(), None).await.expect("open failed");
    let pages = engine.page_count(doc).await.expect("page_count failed");
    assert_eq!(pages, 1, "the engine created a one-page PDF");

    // Page size comes from the engine's page inspection (letter: 612x792).
    let size = engine.page_size(doc, 1).await.expect("page_size failed");
    assert!((size.width - 612.0).abs() < 1.0 && (size.height - 792.0).abs() < 1.0, "unexpected size {:?}", (size.width, size.height));

    // Render at 96 dpi: 612pt = 8.5in = 816px, 792pt = 1056px.
    let png = engine.render_page_png(doc, 1, 96).await.expect("render failed");
    let (w, h) = png_dimensions(&png);
    assert_eq!((w, h), (816, 1056), "unexpected raster size");

    // Out-of-range and 0-based page requests are rejected, not panicked.
    assert!(engine.render_page_png(doc, 0, 96).await.is_err());
    assert!(engine.render_page_png(doc, 2, 96).await.is_err());
    assert!(engine.page_size(doc, 99).await.is_err());
    assert!(engine.page_count(4242).await.is_err(), "an unknown handle must error, not panic");

    // Save: the working file round-trips through another open.
    let saved = engine.save(doc).await.expect("save failed");
    assert!(saved.starts_with(b"%PDF"), "the working file is not a PDF");
    let doc2 = engine.open("saved.pdf".to_owned(), saved, None).await.expect("re-open of the saved file failed");
    assert_eq!(engine.page_count(doc2).await.expect("page_count failed"), 1, "the saved file must keep its page count");

    // Password path: an empty password round-trips.
    let doc3 = engine.open("again.pdf".to_owned(), source.to_vec(), Some(String::new())).await.expect("open with a password failed");
    let png3 = engine.render_page_png(doc3, 1, 72).await.expect("render at 72 dpi failed");
    assert_eq!(png_dimensions(&png3), (612, 792));

    engine.close(doc).await.expect("close failed");
    assert!(engine.page_count(doc).await.is_err(), "a closed handle must error");
}
