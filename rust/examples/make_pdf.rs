// Generates a real test PDF with the PdfCraft engine: `cargo run --example make_pdf -- out.pdf`.

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let path = std::env::args().nth(1).ok_or("usage: make_pdf <out.pdf>")?;
    let session = pdfcraft_engine::Session::new();
    let page = session.create_from_text(
        "test",
        "Hello from PdfCraft Mobile.\n\nThe engine rendered this page.",
    )?;
    let bytes = session.combine(&[
        ("page-1.pdf".to_owned(), page.clone()),
        ("page-2.pdf".to_owned(), page),
    ])?;
    std::fs::write(&path, bytes.as_slice())?;
    println!("wrote {path} ({} bytes)", bytes.len());
    Ok(())
}
