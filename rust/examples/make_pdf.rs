// Generates a real test PDF with the PdfCraft engine: `cargo run --example make_pdf -- out.pdf`.

fn main() {
    let path = std::env::args().nth(1).expect("usage: make_pdf <out.pdf>");
    let session = pdfcraft_engine::Session::new();
    let bytes = session
        .create_from_text("test", "Hello from PdfCraft Mobile.\n\nThe engine rendered this page.")
        .expect("create_from_text failed");
    std::fs::write(&path, bytes.as_slice()).expect("write failed");
    println!("wrote {path} ({} bytes)", bytes.len());
}
