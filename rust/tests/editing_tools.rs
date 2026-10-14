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
    // Date placement sends no text: the engine formats today itself.
    run(
        &engine,
        doc,
        "fill_sign_add",
        r#"{"page":1,"type":"date","at":[72,720]}"#,
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

    // Fill & Sign check mark placed like the touch mark placer does.
    run(
        &engine,
        doc,
        "fill_sign_add",
        r#"{"page":1,"type":"check","at":[72,500]}"#,
    )
    .await;

    // Export the first page as an image and confirm a file lands on disk.
    let out = run(
        &engine,
        doc,
        "doc_export_images",
        r#"{"folder":"outputs/images","format":"png","pages":[1]}"#,
    )
    .await;
    let files = out
        .get(0)
        .and_then(|first| first.get("files"))
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default();
    assert_eq!(files.len(), 1, "one page must produce one image");
    let png = engine
        .read_output(
            files[0]
                .as_str()
                .expect("image output path must be a string")
                .to_owned(),
        )
        .await
        .expect("exported image missing");
    assert!(png.starts_with(&[0x89, b'P', b'N', b'G']), "not a PNG");

    // Forms: author a field, then fill it.
    run(
        &engine,
        doc,
        "form_add_field",
        r#"{"page":1,"type":"text","rect":[72,400,400,430],"name":"t1"}"#,
    )
    .await;
    run(&engine, doc, "form_fill", r#"{"values":{"t1":"filled"}}"#).await;

    // Insert pages from another file after the current page.
    let staged = engine
        .stage_file("insert.pdf".to_owned(), source.to_vec())
        .await
        .expect("stage insert source");
    let before = engine.page_count(doc).await.expect("count");
    run(
        &engine,
        doc,
        "page_insert_file",
        &format!(r#"{{"path":"{staged}","at":{}}}"#, before + 1),
    )
    .await;
    assert_eq!(engine.page_count(doc).await.expect("count"), before + 1);

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
    let opt = run(
        &engine,
        doc,
        "doc_optimize",
        r#"{"path":"outputs/small.pdf"}"#,
    )
    .await;
    assert_eq!(opt[0]["path"], "outputs/small.pdf");
    let small = engine
        .read_output(opt[0]["path"].as_str().expect("opt path").to_owned())
        .await
        .expect("optimized PDF missing");
    assert!(small.starts_with(b"%PDF"));
    run(&engine, doc, "ocr_status", "{}").await;
    run(
        &engine,
        doc,
        "doc_compare",
        r#"{"other":"outputs/one.pdf"}"#,
    )
    .await;
    let rep = run(
        &engine,
        doc,
        "doc_compare_report",
        r#"{"other":"outputs/one.pdf","path":"outputs/report.pdf"}"#,
    )
    .await;
    assert_eq!(rep[0]["path"], "outputs/report.pdf");
    let report = engine
        .read_output(rep[0]["path"].as_str().expect("report path").to_owned())
        .await
        .expect("compare report missing");
    assert!(report.starts_with(b"%PDF"));

    // Standard stamp, page image, header/footer + watermark options.
    run(
        &engine,
        doc,
        "comment_add",
        r#"{"page":1,"type":"stamp","stamp":"approved","at":[300,400]}"#,
    )
    .await;
    let shot = engine
        .render_page_png(doc, 1, 72)
        .await
        .expect("render for image stamp");
    let picture = engine
        .stage_file("pic.png".to_owned(), shot)
        .await
        .expect("stage picture");
    run(
        &engine,
        doc,
        "page_add_image",
        &format!(r#"{{"page":1,"path":"{picture}","rect":[72,600,272,750]}}"#),
    )
    .await;
    let target_opt = run(
        &engine,
        doc,
        "doc_optimize",
        r#"{"path":"outputs/compressed.pdf","color":{"downsample":true,"ppi":50,"above_ppi":50,"compression":"jpeg","quality":26}}"#,
    )
    .await;
    assert_eq!(target_opt[0]["path"], "outputs/compressed.pdf");
    assert!(target_opt[0]["bytes_after"].as_u64().unwrap_or(0) > 0);
    run(
        &engine,
        doc,
        "doc_header_footer",
        r#"{"header_center":"Draft","footer_center":"Page <<1>>"}"#,
    )
    .await;
    run(
        &engine,
        doc,
        "doc_watermark",
        r#"{"text":"W","opacity":0.3,"behind":true}"#,
    )
    .await;
    run(&engine, doc, "doc_remove_marks", r#"{"kind":"watermark"}"#).await;

    // Measure, then export the values; reset the filled form.
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
        "measure_export",
        r#"{"out":"outputs/measures.csv"}"#,
    )
    .await;
    let measures = engine
        .read_output("outputs/measures.csv".to_owned())
        .await
        .expect("measurements CSV missing");
    assert!(!measures.is_empty());
    run(&engine, doc, "form_reset", "{}").await;

    // Replace the first page with the staged source file.
    run(
        &engine,
        doc,
        "page_replace",
        &format!(r#"{{"pages":[1],"path":"{staged}"}}"#),
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
