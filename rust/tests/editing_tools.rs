// Bridge coverage for every bespoke editing UI: each tool the touch UIs
// call is exercised through Engine::execute_tool on the real engine.

use pdfcraft_mobile_api::Engine;
use serde_json::Value;

async fn run(engine: &Engine, doc: u32, tool: &str, args: &str) -> Value {
    let response = engine
        .execute_tool(doc, tool.to_owned(), args.to_owned())
        .await
        .unwrap_or_else(|error| panic!("{tool} {args} failed: {error}"));
    // Document-less tools report an empty status by design.
    if !matches!(tool, "doc_combine" | "ocr_status") {
        assert!(response.status.page_count >= 1, "{tool} returned no pages");
    }
    let texts: Vec<String> = response
        .contents
        .iter()
        .map(|content| content.json.clone())
        .collect();
    serde_json::from_str(&format!("[{}]", texts.join(","))).unwrap_or(Value::Null)
}

fn has_text(value: &Value, needle: &str) -> bool {
    value.to_string().contains(needle)
}

#[tokio::test]
async fn editing_tools_end_to_end() {
    let workspace = tempfile::tempdir().expect("create app sandbox");
    let engine = Engine::new(workspace.path().to_string_lossy().into_owned());
    let source = pdfcraft_engine::Session::new()
        .create_from_text("hello", "Hello PdfCraft Mobile")
        .expect("engine could not create a test PDF");
    let doc = engine
        .open("hello.pdf".to_owned(), source.to_vec(), None)
        .await
        .expect("open failed");

    // Text selection quads (Select mode) highlight whole touched lines.
    let out = run(&engine, doc, "text_lines", r#"{"page":1}"#).await;
    assert!(has_text(&out, "Hello"), "text_lines must list the line");
    let out = run(
        &engine,
        doc,
        "comment_add",
        r#"{"page":1,"type":"highlight","quads":[[10,10,200,10,10,30,200,30]]}"#,
    )
    .await;
    assert!(has_text(&out, "Highlight") || has_text(&out, "doc"));

    // Tap-to-place text and added content.
    run(
        &engine,
        doc,
        "page_add_text",
        r#"{"page":1,"text":"Stamped by test","at":[400,700],"size":14}"#,
    )
    .await;
    run(
        &engine,
        doc,
        "fill_sign_add",
        r#"{"page":1,"type":"text","at":[72,700],"text":"OK"}"#,
    )
    .await;

    // Redact phrase, then apply and confirm the text is gone.
    run(&engine, doc, "redact_mark", r#"{"find":"Hello"}"#).await;
    run(&engine, doc, "redact_apply", "{}").await;
    let out = run(&engine, doc, "text_find", r#"{"query":"Hello"}"#).await;
    assert!(
        !has_text(&out, "Hello PdfCraft"),
        "applied redaction must remove the text"
    );

    // Measure, labels, marks, crop.
    run(
        &engine,
        doc,
        "measure_distance",
        r#"{"page":1,"points":[[72,72],[200,72]]}"#,
    )
    .await;
    run(
        &engine,
        doc,
        "page_number",
        r#"{"from":1,"to":1,"style":"lower-roman"}"#,
    )
    .await;
    run(&engine, doc, "doc_watermark", r#"{"text":"DRAFT"}"#).await;
    run(&engine, doc, "page_set_box", r#"{"margins":[36,36,36,36]}"#).await;

    // Organize: duplicate, move, extract, split, combine.
    run(&engine, doc, "page_duplicate", r#"{"pages":[1]}"#).await;
    assert_eq!(engine.page_count(doc).await.expect("count"), 2);
    run(&engine, doc, "page_move", r#"{"pages":[2],"to":1}"#).await;
    run(
        &engine,
        doc,
        "page_extract",
        r#"{"pages":[1],"out":"outputs/one.pdf"}"#,
    )
    .await;
    let one = engine
        .read_output("outputs/one.pdf".to_owned())
        .await
        .expect("extracted file missing");
    assert!(one.starts_with(b"%PDF"));
    run(
        &engine,
        doc,
        "doc_split",
        r#"{"every":1,"out_dir":"outputs/split"}"#,
    )
    .await;
    run(
        &engine,
        doc,
        "doc_combine",
        r#"{"paths":["outputs/one.pdf","outputs/one.pdf"],"out":"outputs/two.pdf"}"#,
    )
    .await;
    let two = engine
        .read_output("outputs/two.pdf".to_owned())
        .await
        .expect("combined file missing");
    assert!(two.starts_with(b"%PDF"));

    // Forms: author a field, then fill it.
    run(
        &engine,
        doc,
        "form_add_field",
        r#"{"page":1,"type":"text","rect":[72,400,400,430],"name":"t1"}"#,
    )
    .await;
    run(&engine, doc, "form_fill", r#"{"values":{"t1":"filled"}}"#).await;

    // Export, optimize, OCR status, compare.
    run(
        &engine,
        doc,
        "doc_export_text",
        r#"{"path":"outputs/export.txt"}"#,
    )
    .await;
    let text = engine
        .read_output("outputs/export.txt".to_owned())
        .await
        .expect("exported text missing");
    assert!(!text.is_empty());
    run(
        &engine,
        doc,
        "doc_optimize",
        r#"{"path":"outputs/small.pdf"}"#,
    )
    .await;
    run(&engine, doc, "ocr_status", "{}").await;
    run(
        &engine,
        doc,
        "doc_compare",
        r#"{"other":"outputs/one.pdf"}"#,
    )
    .await;

    // Protect with a password, then reopen with it (encrypted-fixture flow).
    run(&engine, doc, "doc_protect", r#"{"open_password":"secret"}"#).await;
    let snapshot = engine.save_snapshot(doc).await.expect("snapshot");
    engine
        .commit_save(doc, snapshot.token)
        .await
        .expect("commit");
    let locked = engine
        .open("locked.pdf".to_owned(), snapshot.bytes.clone(), None)
        .await;
    assert!(locked.is_err(), "opening without the password must fail");
    let unlocked = engine
        .open(
            "locked.pdf".to_owned(),
            snapshot.bytes,
            Some("secret".to_owned()),
        )
        .await
        .expect("opening with the password failed");
    engine
        .close(unlocked, true)
        .await
        .expect("close unlocked failed");

    engine.close(doc, true).await.expect("close failed");
}
