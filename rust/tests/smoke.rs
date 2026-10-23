// End-to-end mobile operation test against the existing PdfCraft automation registry and engine.

use pdfcraft_mobile_api::Engine;

fn png_dimensions(png: &[u8]) -> (u32, u32) {
    assert!(png.starts_with(&[0x89, b'P', b'N', b'G']), "not a PNG");
    assert_eq!(&png[12..16], b"IHDR", "missing IHDR");
    let w = u32::from_be_bytes([png[16], png[17], png[18], png[19]]);
    let h = u32::from_be_bytes([png[20], png[21], png[22], png[23]]);
    (w, h)
}

#[tokio::test]
async fn manual_operation_catalog_edit_undo_save_reopen() {
    let workspace = tempfile::tempdir().expect("create app sandbox");
    let engine = Engine::new(workspace.path().to_string_lossy().into_owned());
    let source = pdfcraft_engine::Session::new()
        .create_from_text("hello", "Hello PdfCraft Mobile")
        .expect("engine could not create a test PDF");
    assert!(
        source.len() > 500,
        "engine produced a suspiciously small PDF"
    );

    let catalog = engine
        .operation_catalog()
        .await
        .expect("operation catalog failed");
    for required in [
        "page_rotate",
        "page_delete",
        "comment_add",
        "form_fields",
        "edit_undo",
    ] {
        assert!(
            catalog.iter().any(|operation| operation.id == required),
            "missing {required}"
        );
    }
    assert!(
        catalog
            .iter()
            .all(|operation| !operation.input_schema_json.contains("\"doc\""))
    );

    let doc = engine
        .open("hello.pdf".to_owned(), source.to_vec(), None)
        .await
        .expect("open failed");
    assert_eq!(engine.page_count(doc).await.expect("page count failed"), 1);

    let before = engine.page_size(doc, 1).await.expect("page size failed");
    assert!((before.width - 612.0).abs() < 1.0 && (before.height - 792.0).abs() < 1.0);

    let rendered = engine
        .render_page_png(doc, 1, 96)
        .await
        .expect("render failed");
    assert_eq!(png_dimensions(&rendered), (816, 1056));

    let rotated = engine
        .execute_tool(
            doc,
            "page_rotate".to_owned(),
            r#"{"pages":[1],"degrees":90}"#.to_owned(),
        )
        .await
        .expect("page rotate operation failed");
    assert!(rotated.status.dirty);
    assert_eq!(rotated.status.can_undo, "Rotate page");
    let after = engine
        .page_size(doc, 1)
        .await
        .expect("rotated page size failed");
    assert!((after.width - before.height).abs() < 1.0 && (after.height - before.width).abs() < 1.0);

    let undone = engine
        .execute_tool(doc, "edit_undo".to_owned(), "{}".to_owned())
        .await
        .expect("undo operation failed");
    assert_eq!(undone.status.can_undo, "");
    assert_eq!(undone.status.can_redo, "Rotate page");

    let redone = engine
        .execute_tool(doc, "edit_redo".to_owned(), "{}".to_owned())
        .await
        .expect("redo operation failed");
    assert_eq!(redone.status.can_undo, "Rotate page");

    // Editing existing text through the same operation bridge the UI uses.
    let edited = engine
        .execute_tool(
            doc,
            "text_edit".to_owned(),
            r#"{"page":1,"paragraph":1,"text":"Hello from the bridge"}"#.to_owned(),
        )
        .await
        .expect("text_edit operation failed");
    assert!(edited.status.dirty);
    let found = engine
        .execute_tool(
            doc,
            "text_find".to_owned(),
            r#"{"query":"from the bridge"}"#.to_owned(),
        )
        .await
        .expect("text_find operation failed");
    assert!(
        found
            .contents
            .iter()
            .any(|content| content.json.contains("from the bridge")),
        "edited text must be searchable"
    );

    // Bookmark add/list round-trip through the bridge.
    engine
        .execute_tool(
            doc,
            "bookmark_add".to_owned(),
            r#"{"title":"Bridge mark","page":1}"#.to_owned(),
        )
        .await
        .expect("bookmark_add operation failed");
    let listed = engine
        .execute_tool(doc, "bookmark_list".to_owned(), "{}".to_owned())
        .await
        .expect("bookmark_list operation failed");
    assert!(
        listed
            .contents
            .iter()
            .any(|content| content.json.contains("Bridge mark")),
        "new bookmark must be listed"
    );

    assert!(
        engine
            .execute_tool(
                doc,
                "page_rotate".to_owned(),
                r#"{"pages":[1],"degrees":45}"#.to_owned()
            )
            .await
            .is_err()
    );
    assert!(
        engine
            .execute_tool(doc, "doc_save".to_owned(), "{}".to_owned())
            .await
            .is_err(),
        "file lifecycle tools stay behind mobile-safe methods"
    );
    assert!(engine.render_page_png(doc, 0, 96).await.is_err());
    assert!(engine.status(4242).await.is_err());

    let snapshot = engine
        .save_snapshot(doc)
        .await
        .expect("save snapshot failed");
    assert!(snapshot.bytes.starts_with(b"%PDF"));
    assert!(
        engine.close(doc, false).await.is_err(),
        "dirty documents must not close silently"
    );

    let reopened = engine
        .open("saved.pdf".to_owned(), snapshot.bytes.clone(), None)
        .await
        .expect("saved bytes did not reopen");
    assert_eq!(
        engine
            .page_count(reopened)
            .await
            .expect("reopened page count failed"),
        1
    );
    assert_eq!(
        png_dimensions(
            &engine
                .render_page_png(reopened, 1, 72)
                .await
                .expect("reopen render failed")
        ),
        (792, 612)
    );

    engine
        .commit_save(doc, snapshot.token)
        .await
        .expect("mark saved failed");
    assert!(!engine.status(doc).await.expect("status failed").dirty);
    engine
        .close(doc, false)
        .await
        .expect("clean document close failed");
    engine
        .close(reopened, false)
        .await
        .expect("reopened document close failed");
    assert!(engine.status(doc).await.is_err());

    let bad = engine
        .open("bad.pdf".to_owned(), b"not a PDF".to_vec(), None)
        .await;
    assert!(bad.is_err(), "malformed PDFs must be reported as errors");

    let staged = engine
        .stage_file("../unsafe-name.txt".to_owned(), b"safe".to_vec())
        .await
        .expect("stage file failed");
    assert!(!staged.contains(".."));
    assert_eq!(
        engine
            .read_output(staged)
            .await
            .expect("read staged file failed"),
        b"safe"
    );
    assert!(
        engine
            .read_output("../../etc/passwd".to_owned())
            .await
            .is_err()
    );
}

#[tokio::test]
async fn mobile_can_create_a_pdf_from_staged_files_without_opening_a_hidden_document() {
    let workspace = tempfile::tempdir().expect("create app sandbox");
    let engine = Engine::new(workspace.path().to_string_lossy().into_owned());
    let input = pdfcraft_engine::Session::new()
        .create_from_text("photo-source", "Image conversion source")
        .expect("create source PDF");
    let doc = engine
        .open("current.pdf".to_owned(), input.to_vec(), None)
        .await
        .expect("open current document");
    let photo = engine
        .render_page_png(doc, 1, 72)
        .await
        .expect("render source image");
    let staged = engine
        .stage_file("photo.png".to_owned(), photo)
        .await
        .expect("stage photo");
    let catalog = engine
        .operation_catalog()
        .await
        .expect("load mobile operation catalog");
    for required in [
        "doc_create_multiple",
        "fill_sign_date_format",
        "ocr_recognize_files",
    ] {
        assert!(
            catalog.iter().any(|operation| operation.id == required),
            "missing {required} from the mobile operation catalog"
        );
    }

    let created = engine
        .execute_tool(
            doc,
            "doc_create_multiple".to_owned(),
            serde_json::json!({
                "paths": [staged],
                "mode": "combine",
                "out": "outputs/created-from-files.pdf",
                "open": false,
            })
            .to_string(),
        )
        .await
        .expect("create a PDF from staged input");
    assert_eq!(created.status.page_count, 0);
    assert!(
        created
            .contents
            .iter()
            .any(|content| { content.json.contains("created-from-files.pdf") })
    );
    let output = engine
        .read_output("outputs/created-from-files.pdf".to_owned())
        .await
        .expect("read created PDF");
    assert!(output.starts_with(b"%PDF"));

    let date = engine
        .execute_tool(doc, "fill_sign_date_format".to_owned(), "{}".to_owned())
        .await
        .expect("read Fill & Sign date preference");
    assert!(
        date.contents
            .iter()
            .any(|content| { content.json.contains("\"today\"") })
    );
    let older = pdfcraft_engine::Session::new()
        .create_from_text("older", "Older wording")
        .expect("create older comparison PDF");
    let older_path = engine
        .stage_file("older.pdf".to_owned(), older.to_vec())
        .await
        .expect("stage older comparison PDF");
    let marked = engine
        .execute_tool(
            doc,
            "doc_compare_mark".to_owned(),
            serde_json::json!({"other": older_path}).to_string(),
        )
        .await
        .expect("mark comparison differences");
    assert!(
        marked.status.dirty,
        "difference comments should be undoable edits"
    );
    engine
        .close(doc, true)
        .await
        .expect("close current document");
}

#[tokio::test]
async fn mobile_can_create_a_blank_pdf_without_opening_it() {
    let workspace = tempfile::tempdir().expect("create app sandbox");
    let engine = Engine::new(workspace.path().to_string_lossy().into_owned());
    let catalog = engine
        .operation_catalog()
        .await
        .expect("load mobile operation catalog");
    assert!(
        catalog.iter().any(|operation| operation.id == "doc_create"),
        "doc_create must be exposed for blank-PDF creation"
    );
    let created = engine
        .execute_tool(
            0,
            "doc_create".to_owned(),
            serde_json::json!({
                "from": "blank",
                "pages": 3,
                "out": "outputs/blank-test.pdf",
            })
            .to_string(),
        )
        .await
        .expect("create a blank PDF");
    assert!(
        created
            .contents
            .iter()
            .any(|content| { content.json.contains("blank-test.pdf") })
    );
    let output = engine
        .read_output("outputs/blank-test.pdf".to_owned())
        .await
        .expect("read blank PDF");
    assert!(output.starts_with(b"%PDF"));
    // Non-blank sources stay behind the staged-file flows.
    assert!(
        engine
            .execute_tool(
                0,
                "doc_create".to_owned(),
                serde_json::json!({"from": "images"}).to_string(),
            )
            .await
            .is_err()
    );
}

#[tokio::test]
async fn text_candidate_render_matches_single_commit_and_undo_restores_source() {
    let workspace = tempfile::tempdir().unwrap();
    let engine = Engine::new(workspace.path().to_string_lossy().into_owned());
    let source = pdfcraft_engine::Session::new()
        .create_from_text("text editing", "Original paragraph for touch editing")
        .unwrap();
    let doc = engine
        .open("text.pdf".into(), source.to_vec(), None)
        .await
        .unwrap();
    let before = engine.render_page_png(doc, 1, 96).await.unwrap();
    let baseline = engine.save_snapshot(doc).await.unwrap();
    engine.cancel_save(doc, baseline.token).await.unwrap();
    let copy = engine
        .open("preview.pdf".into(), baseline.bytes, None)
        .await
        .unwrap();
    let args = r#"{"page":1,"paragraph":1,"text":"A reviewed replacement paragraph","width":250,"size":15}"#;
    engine
        .execute_tool(copy, "text_edit".into(), args.into())
        .await
        .unwrap();
    let preview = engine.render_page_png(copy, 1, 96).await.unwrap();
    if let Ok(directory) = std::env::var("TEXT_EDIT_PREVIEW_DIR") {
        std::fs::create_dir_all(&directory).unwrap();
        std::fs::write(format!("{directory}/before.png"), &before).unwrap();
        std::fs::write(format!("{directory}/preview.png"), &preview).unwrap();
        let source_blocks = engine
            .execute_tool(doc, "text_paragraphs".into(), r#"{"page":1}"#.into())
            .await
            .unwrap();
        let preview_blocks = engine
            .execute_tool(copy, "text_paragraphs".into(), r#"{"page":1}"#.into())
            .await
            .unwrap();
        std::fs::write(
            format!("{directory}/before.json"),
            &source_blocks.contents[0].json,
        )
        .unwrap();
        std::fs::write(
            format!("{directory}/preview.json"),
            &preview_blocks.contents[0].json,
        )
        .unwrap();
    }
    assert_ne!(preview, before);
    assert_eq!(engine.render_page_png(doc, 1, 96).await.unwrap(), before);
    assert!(
        !engine.status(doc).await.unwrap().dirty,
        "preview dirtied the source"
    );
    engine.close(copy, true).await.unwrap();
    let committed = engine
        .execute_tool(doc, "text_edit".into(), args.into())
        .await
        .unwrap();
    assert!(committed.status.dirty);
    assert_eq!(engine.render_page_png(doc, 1, 96).await.unwrap(), preview);
    engine
        .execute_tool(doc, "edit_undo".into(), "{}".into())
        .await
        .unwrap();
    assert_eq!(engine.render_page_png(doc, 1, 96).await.unwrap(), before);
    let snapshot = engine.save_snapshot(doc).await.unwrap();
    engine.cancel_save(doc, snapshot.token).await.unwrap();
    let reopened = engine
        .open("reopened.pdf".into(), snapshot.bytes, None)
        .await
        .unwrap();
    assert_eq!(
        engine.render_page_png(reopened, 1, 96).await.unwrap(),
        before
    );
    engine.close(reopened, true).await.unwrap();
    engine.close(doc, true).await.unwrap();
}
