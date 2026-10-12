// Builds a one-page PDF containing a real AcroForm (text + checkbox) for
// device-testing the Fill form UI: `cargo run --example make_form -- out.pdf`.

use pdfcraft_automation::Automation;
use serde_json::json;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let path = std::env::args()
        .nth(1)
        .ok_or("usage: make_form <out.pdf>")?;
    let workspace = tempfile::tempdir()?;
    let mut automation = Automation::new().with_root(workspace.path().to_path_buf())?;

    let source =
        pdfcraft_engine::Session::new().create_from_text("form", "Please fill in this form.")?;
    std::fs::write(workspace.path().join("form.pdf"), source.as_slice())?;
    let doc = automation
        .call("doc_open", &json!({"path": "form.pdf"}))?
        .into_iter()
        .find_map(|content| match content {
            pdfcraft_automation::Content::Json(value) => Some(value),
            _ => None,
        })
        .ok_or("doc_open returned no summary")?;
    let id = doc["doc"].as_u64().ok_or("no doc id")?;

    for (name, kind, rect) in [
        ("full_name", "text", json!([72.0, 200.0, 400.0, 230.0])),
        ("newsletter", "checkbox", json!([72.0, 260.0, 92.0, 280.0])),
    ] {
        automation.call(
            "form_add_field",
            &json!({"doc": id, "page": 1, "type": kind, "rect": rect, "name": name}),
        )?;
    }
    let saved = automation.call("doc_save", &json!({"doc": id, "path": "form-filled.pdf"}))?;
    let saved_path = saved
        .into_iter()
        .find_map(|content| match content {
            pdfcraft_automation::Content::Json(value) => value["path"].as_str().map(str::to_owned),
            _ => None,
        })
        .ok_or("doc_save returned no path")?;
    std::fs::copy(workspace.path().join(saved_path), &path)?;
    println!("wrote {path}");
    Ok(())
}
