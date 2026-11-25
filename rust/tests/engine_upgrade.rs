use pdfcraft_mobile_api::Engine;
use serde_json::{Value, json};

async fn call(engine: &Engine, handle: u32, name: &str, args: Value) -> Value {
    let response = engine
        .execute_tool(handle, name.to_owned(), args.to_string())
        .await
        .unwrap_or_else(|error| panic!("{name} failed: {error}"));
    serde_json::from_str(&response.contents[0].json).unwrap()
}

#[tokio::test]
async fn mobile_schema_matches_execution_for_two_pdfs_and_documentless_tools() {
    let workspace = tempfile::tempdir().unwrap();
    let engine = Engine::new(workspace.path().to_string_lossy().into_owned());
    let catalog = engine.operation_catalog().await.unwrap();
    assert_eq!(catalog.len(), 200);
    for (name, key) in [
        ("bookmark_copy", "from"),
        ("doc_compare", "other"),
        ("accessibility_review_html", "before"),
        ("accessibility_review_record", "before"),
    ] {
        let op = catalog.iter().find(|op| op.id == name).unwrap();
        let schema: Value = serde_json::from_str(&op.input_schema_json).unwrap();
        assert!(op.requires_document);
        assert_eq!(schema["properties"][key]["format"], "pdf-file");
        assert!(schema["properties"].get("after").is_none());
    }

    let create_args = json!({"from":"text","text":"Read the report","out":"outputs/source.pdf"});
    call(&engine, 0, "doc_create", create_args).await;
    let bytes = engine
        .read_output("outputs/source.pdf".into())
        .await
        .unwrap();
    let doc = engine.open("index.pdf".into(), bytes, None).await.unwrap();
    let count = call(&engine, doc, "text_word_count", json!({})).await;
    assert_eq!(count["total"]["words"], 3);
    let replaced = call(
        &engine,
        doc,
        "text_replace",
        json!({"find":"report","replace":"letter"}),
    )
    .await;
    assert_eq!(replaced["replaced"], 1);
    call(
        &engine,
        doc,
        "bookmark_add",
        json!({"title":"Reference","page":1}),
    )
    .await;
    let snapshot = engine.save_snapshot(doc).await.unwrap();
    let imported = engine
        .stage_file("with-bookmark.pdf".into(), snapshot.bytes)
        .await
        .unwrap();
    engine.cancel_save(doc, snapshot.token).await.unwrap();
    call(&engine, doc, "bookmark_copy", json!({"from":imported})).await;
    call(
        &engine,
        doc,
        "page_add_text",
        json!({"page":1,"text":"Copied stamp","at":[60,80]}),
    )
    .await;
    let copied = call(
        &engine,
        doc,
        "content_copy",
        json!({"page":1,"index":1,"to_doc":imported}),
    )
    .await;
    let copy = engine
        .read_output(copied["path"].as_str().unwrap().into())
        .await
        .unwrap();
    let target = engine.open("copied.pdf".into(), copy, None).await.unwrap();
    let content = call(&engine, target, "text_extract", json!({"pages":[1]})).await;
    assert!(content.to_string().contains("Copied stamp"), "{content}");
    engine.close(target, false).await.unwrap();
    for (name, out) in [
        ("accessibility_review_html", "outputs/review.html"),
        ("accessibility_review_record", "outputs/review.json"),
    ] {
        call(&engine, doc, name, json!({"before":imported,"path":out})).await;
        assert!(!engine.read_output(out.into()).await.unwrap().is_empty());
    }
    let batch = call(
        &engine,
        0,
        "doc_batch",
        json!({"paths":[imported],"out_dir":"outputs/batch","steps":["optimize"]}),
    )
    .await;
    assert_eq!(batch["completed"], 1);
    let bates = call(
        &engine,
        0,
        "doc_bates_multi",
        json!({"files":[{"input":imported,"output":"outputs/numbered.pdf"}]}),
    )
    .await;
    assert!(
        engine
            .read_output("outputs/numbered.pdf".into())
            .await
            .unwrap()
            .starts_with(b"%PDF"),
        "{bates}"
    );

    let escaped = workspace
        .path()
        .parent()
        .unwrap()
        .join("out-of-workspace.pdf");
    assert!(
        engine
            .execute_tool(
                0,
                "doc_create".into(),
                json!({"from":"blank","out":escaped}).to_string()
            )
            .await
            .is_err()
    );
    let snapshot = engine.save_snapshot(doc).await.unwrap();
    engine.commit_save(doc, snapshot.token).await.unwrap();
    let renamed = call(&engine, doc, "doc_rename", json!({"name":"saved.pdf"})).await;
    let working_copy = workspace.path().join(renamed["path"].as_str().unwrap());
    assert_eq!(working_copy.file_name().unwrap(), "saved.pdf");
    assert!(working_copy.is_file());
    call(
        &engine,
        doc,
        "doc_set_info",
        json!({"key":"Title","value":"Last change"}),
    )
    .await;
    let snapshot = engine.save_snapshot(doc).await.unwrap();
    engine.commit_save(doc, snapshot.token).await.unwrap();
    assert!(std::fs::read(&working_copy).unwrap().starts_with(b"%PDF"));
    engine.close(doc, false).await.unwrap();
    assert!(!working_copy.exists());
}

fn pdf_from_objects(objects: &[&str]) -> Vec<u8> {
    let mut pdf = String::from("%PDF-1.7\n");
    let mut offsets = Vec::new();
    for (index, object) in objects.iter().enumerate() {
        offsets.push(pdf.len());
        pdf.push_str(&format!("{} 0 obj\n{object}\nendobj\n", index + 1));
    }
    let xref = pdf.len();
    pdf.push_str(&format!(
        "xref\n0 {}\n0000000000 65535 f \n",
        objects.len() + 1
    ));
    for offset in offsets {
        pdf.push_str(&format!("{offset:010} 00000 n \n"));
    }
    pdf.push_str(&format!(
        "trailer\n<< /Size {} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n",
        objects.len() + 1
    ));
    pdf.into_bytes()
}

#[tokio::test]
async fn file_picker_can_supply_a_relative_pdf_link_without_leaving_hidden_documents() {
    let workspace = tempfile::tempdir().unwrap();
    let engine = Engine::new(workspace.path().to_string_lossy().into_owned());
    let objects = [
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 /MediaBox [0 0 200 300] >>",
        "<< /Type /Page /Parent 2 0 R /Annots [4 0 R] >>",
        "<< /Type /Annot /Subtype /Link /Rect [10 10 80 30] /A << /S /GoToR /F (files/second.pdf) /D [1 /Fit] >> >>",
    ];
    let doc = engine
        .open("first.pdf".into(), pdf_from_objects(&objects), None)
        .await
        .unwrap();
    let target = pdfcraft_engine::Session::new()
        .create_blank(200.0, 300.0, 2)
        .unwrap();
    let selected = engine
        .stage_file("second.pdf".into(), target.to_vec())
        .await
        .unwrap();
    for _ in 0..2 {
        let out = call(
            &engine,
            doc,
            "link_open",
            json!({"page":1,"index":1,"linked_file":selected}),
        )
        .await;
        assert_eq!(out["destination"]["page"], 2);
        assert_eq!(out["destination_applied"], true);
        assert!(
            engine
                .read_output(out["path"].as_str().unwrap().into())
                .await
                .unwrap()
                .starts_with(b"%PDF")
        );
    }
    assert!(engine.read_output(selected).await.is_ok());
    assert_eq!(engine.page_count(doc).await.unwrap(), 1);
    engine.close(doc, false).await.unwrap();
}

#[tokio::test]
async fn save_as_runs_the_will_save_event_once_and_a_cancel_keeps_external_edits_dirty() {
    let workspace = tempfile::tempdir().unwrap();
    let engine = Engine::new(workspace.path().to_string_lossy().into_owned());
    let bytes = pdf_from_objects(&[
        r"<< /Type /Catalog /Pages 2 0 R /AcroForm << /Fields [4 0 R] /DA (/Helv 12 Tf 0 g) /DR << /Font << /Helv 5 0 R >> >> >> /AA << /WS 6 0 R >> >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 /MediaBox [0 0 200 300] >>",
        "<< /Type /Page /Parent 2 0 R /Annots [4 0 R] >>",
        "<< /Type /Annot /Subtype /Widget /FT /Tx /T (log) /V (draft) /Rect [10 20 100 60] /P 3 0 R >>",
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>",
        r"<< /S /JavaScript /JS (var f=getField\('log'\); f.value=f.valueAsString+'x';) >>",
    ]);
    let doc = engine
        .open("scripted.pdf".into(), bytes, None)
        .await
        .unwrap();
    let preview = engine.save_snapshot(doc).await.unwrap();
    engine.cancel_save(doc, preview.token).await.unwrap();
    assert!(!engine.status(doc).await.unwrap().dirty);

    let first = engine.prepare_save_as(doc).await.unwrap();
    engine.cancel_save(doc, first.token).await.unwrap();
    assert!(engine.status(doc).await.unwrap().dirty);
    assert!(engine.close(doc, false).await.is_err());

    let second = engine.prepare_save_as(doc).await.unwrap();
    engine.commit_save(doc, second.token).await.unwrap();
    assert!(!engine.status(doc).await.unwrap().dirty);
    let saved_doc = engine
        .open("saved.pdf".into(), second.bytes, None)
        .await
        .unwrap();
    for handle in [doc, saved_doc] {
        let fields = call(&engine, handle, "form_fields", json!({})).await;
        assert!(fields.to_string().contains(r#""draftxx""#), "{fields}");
        engine.close(handle, false).await.unwrap();
    }
}
