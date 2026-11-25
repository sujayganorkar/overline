use std::collections::HashMap;
use std::fs;
use std::path::{Component, Path, PathBuf};
use std::sync::LazyLock;
use std::thread;
use std::time::Duration;

use flutter_rust_bridge::frb;
use pdfcraft_automation::{Automation, Content, ToolDef, tools};
use pdfcraft_engine::DocId;
use serde_json::{Value, json};
use tokio::sync::oneshot;

static TOOL_DEFINITIONS: LazyLock<Vec<ToolDef>> = LazyLock::new(tools);

const COMMAND_QUEUE_CAPACITY: usize = 2;
const OP_TIMEOUT: Duration = Duration::from_secs(120);
const SAVE_TIMEOUT: Duration = Duration::from_secs(180);

struct MobileDoc {
    automation_id: u64,
    staging_path: String,
    directory: tempfile::TempDir,
    awaiting_external_save: bool,
}

#[derive(Clone, Copy)]
struct PendingSave {
    handle: u32,
    automation_id: u64,
    generation: u64,
    prepared_for_export: bool,
}

struct Runtime {
    automation: Automation,
    root: PathBuf,
    docs: HashMap<u32, MobileDoc>,
    pending_saves: HashMap<u32, PendingSave>,
    next_document: u32,
    next_save_token: u32,
    next_file: u32,
}

/// The operation browser uses the same automation tool schemas as PdfCraft's headless interfaces.
pub struct OperationInfo {
    pub id: String,
    pub title: String,
    pub description: String,
    pub input_schema_json: String,
    pub read_only: bool,
    pub destructive: bool,
    pub command_id: String,
    pub requires_document: bool,
}

/// Structured result from an upstream PdfCraft operation. Exactly one payload is populated.
pub struct OperationContent {
    pub json: String,
    pub png: Vec<u8>,
    pub width: u32,
    pub height: u32,
}

pub struct OperationResponse {
    pub contents: Vec<OperationContent>,
    pub status: DocumentStatus,
}

#[derive(Default)]
pub struct DocumentStatus {
    pub page_count: u32,
    pub dirty: bool,
    pub editable: bool,
    pub can_undo: String,
    pub can_redo: String,
}

pub struct SaveSnapshot {
    pub token: u32,
    pub bytes: Vec<u8>,
}

pub struct PageSize {
    pub width: f32,
    pub height: f32,
}

struct OpenReq {
    name: String,
    bytes: Vec<u8>,
    password: Option<String>,
}

enum Cmd {
    Open(OpenReq, oneshot::Sender<Result<u32, String>>),
    Status(u32, oneshot::Sender<Result<DocumentStatus, String>>),
    PageSize(u32, u32, oneshot::Sender<Result<PageSize, String>>),
    Render(u32, u32, u32, oneshot::Sender<Result<Vec<u8>, String>>),
    Catalog(oneshot::Sender<Result<Vec<OperationInfo>, String>>),
    Execute(
        u32,
        String,
        String,
        oneshot::Sender<Result<OperationResponse, String>>,
    ),
    SaveSnapshot(u32, bool, oneshot::Sender<Result<SaveSnapshot, String>>),
    CommitSave(u32, u32, oneshot::Sender<Result<(), String>>),
    CancelSave(u32, u32, oneshot::Sender<Result<(), String>>),
    StageFile(String, Vec<u8>, oneshot::Sender<Result<String, String>>),
    ReadOutput(String, oneshot::Sender<Result<Vec<u8>, String>>),
    Close(u32, bool, oneshot::Sender<Result<(), String>>),
}

/// Flutter's handle. Automation and its engine Session have one owner: the worker thread.
#[frb(opaque)]
pub struct Engine {
    tx: tokio::sync::mpsc::Sender<Cmd>,
    startup_error: Option<String>,
}

#[frb(opaque)]
impl Engine {
    #[frb(sync)]
    pub fn new(workspace: String) -> Self {
        let (tx, rx) = tokio::sync::mpsc::channel(COMMAND_QUEUE_CAPACITY);
        let setup = prepare_runtime(&workspace);
        let startup_error = match setup {
            Ok((automation, root)) => thread::Builder::new()
                .name("pdfcraft-engine".to_owned())
                .spawn(move || worker_main(automation, root, rx))
                .err()
                .map(|error| format!("could not start the PdfCraft worker: {error}")),
            Err(error) => Some(error),
        };
        Self { tx, startup_error }
    }

    pub async fn open(
        &self,
        name: String,
        bytes: Vec<u8>,
        password: Option<String>,
    ) -> Result<u32, String> {
        let (reply, rx) = oneshot::channel();
        self.dispatch(
            Cmd::Open(
                OpenReq {
                    name,
                    bytes,
                    password,
                },
                reply,
            ),
            rx,
            OP_TIMEOUT,
            "open",
        )
        .await
    }

    pub async fn status(&self, handle: u32) -> Result<DocumentStatus, String> {
        let (reply, rx) = oneshot::channel();
        self.dispatch(
            Cmd::Status(handle, reply),
            rx,
            OP_TIMEOUT,
            "document status",
        )
        .await
    }

    pub async fn page_count(&self, handle: u32) -> Result<u32, String> {
        Ok(self.status(handle).await?.page_count)
    }

    pub async fn page_size(&self, handle: u32, page_1based: u32) -> Result<PageSize, String> {
        let (reply, rx) = oneshot::channel();
        self.dispatch(
            Cmd::PageSize(handle, page_1based, reply),
            rx,
            OP_TIMEOUT,
            "page size",
        )
        .await
    }

    pub async fn render_page_png(
        &self,
        handle: u32,
        page_1based: u32,
        dpi: u32,
    ) -> Result<Vec<u8>, String> {
        let (reply, rx) = oneshot::channel();
        self.dispatch(
            Cmd::Render(handle, page_1based, dpi, reply),
            rx,
            SAVE_TIMEOUT,
            "render",
        )
        .await
    }

    pub async fn operation_catalog(&self) -> Result<Vec<OperationInfo>, String> {
        let (reply, rx) = oneshot::channel();
        self.dispatch(Cmd::Catalog(reply), rx, OP_TIMEOUT, "operation catalog")
            .await
    }

    /// Invoke one schema-validated upstream automation tool for the open document.
    pub async fn execute_tool(
        &self,
        handle: u32,
        tool: String,
        arguments_json: String,
    ) -> Result<OperationResponse, String> {
        let (reply, rx) = oneshot::channel();
        self.dispatch(
            Cmd::Execute(handle, tool, arguments_json, reply),
            rx,
            SAVE_TIMEOUT,
            "document operation",
        )
        .await
    }

    pub async fn save_snapshot(&self, handle: u32) -> Result<SaveSnapshot, String> {
        let (reply, rx) = oneshot::channel();
        self.dispatch(
            Cmd::SaveSnapshot(handle, false, reply),
            rx,
            SAVE_TIMEOUT,
            "prepare save",
        )
        .await
    }

    /// Run PDF WillSave actions and prepare the exact bytes for Android's Save As picker.
    pub async fn prepare_save_as(&self, handle: u32) -> Result<SaveSnapshot, String> {
        let (reply, rx) = oneshot::channel();
        self.dispatch(
            Cmd::SaveSnapshot(handle, true, reply),
            rx,
            SAVE_TIMEOUT,
            "prepare Save As",
        )
        .await
    }

    /// Mark a save complete only if the document has not changed since its byte snapshot.
    pub async fn commit_save(&self, handle: u32, token: u32) -> Result<(), String> {
        let (reply, rx) = oneshot::channel();
        self.dispatch(
            Cmd::CommitSave(handle, token, reply),
            rx,
            SAVE_TIMEOUT,
            "commit save",
        )
        .await
    }

    pub async fn cancel_save(&self, handle: u32, token: u32) -> Result<(), String> {
        let (reply, rx) = oneshot::channel();
        self.dispatch(
            Cmd::CancelSave(handle, token, reply),
            rx,
            OP_TIMEOUT,
            "cancel save",
        )
        .await
    }

    /// Copy a user-selected supporting file into the confined mobile workspace. The returned
    /// relative path can be passed to upstream tools that accept an image/data-file path.
    pub async fn stage_file(&self, name: String, bytes: Vec<u8>) -> Result<String, String> {
        let (reply, rx) = oneshot::channel();
        self.dispatch(
            Cmd::StageFile(name, bytes, reply),
            rx,
            OP_TIMEOUT,
            "stage file",
        )
        .await
    }

    /// Read an output path returned by an upstream tool, confined to this app's workspace.
    pub async fn read_output(&self, path: String) -> Result<Vec<u8>, String> {
        let (reply, rx) = oneshot::channel();
        self.dispatch(
            Cmd::ReadOutput(path, reply),
            rx,
            SAVE_TIMEOUT,
            "read output",
        )
        .await
    }

    pub async fn close(&self, handle: u32, discard_changes: bool) -> Result<(), String> {
        let (reply, rx) = oneshot::channel();
        self.dispatch(
            Cmd::Close(handle, discard_changes, reply),
            rx,
            OP_TIMEOUT,
            "close document",
        )
        .await
    }

    async fn dispatch<T>(
        &self,
        command: Cmd,
        reply: oneshot::Receiver<Result<T, String>>,
        timeout: Duration,
        operation: &str,
    ) -> Result<T, String> {
        if let Some(error) = &self.startup_error {
            return Err(error.clone());
        }
        // Once queued, a native edit cannot be cancelled by dropping its reply. In particular
        // batch jobs and OCR can take minutes; a timeout here would invite a duplicate edit.
        tokio::time::timeout(timeout, self.tx.send(command))
            .await
            .map_err(|_| format!("engine is busy: {operation} could not be queued"))?
            .map_err(worker_gone)?;
        reply.await.map_err(worker_gone)?
    }
}

fn worker_gone<T>(_: T) -> String {
    "PdfCraft worker thread is unavailable".to_owned()
}

fn prepare_runtime(workspace: &str) -> Result<(Automation, PathBuf), String> {
    if workspace.trim().is_empty() {
        return Err("the app workspace path is empty".to_owned());
    }
    let path = PathBuf::from(workspace);
    fs::create_dir_all(&path).map_err(|error| format!("create app workspace: {error}"))?;
    let root = path
        .canonicalize()
        .map_err(|error| format!("resolve app workspace: {error}"))?;
    let automation = Automation::new()
        .with_root(root.clone())
        .map_err(|error| format!("initialize confined PdfCraft workspace: {error}"))?;
    Ok((automation, root))
}

fn catch_panic<F, T>(f: F, context: &str) -> Result<T, String>
where
    F: FnOnce() -> Result<T, String>,
{
    match std::panic::catch_unwind(std::panic::AssertUnwindSafe(f)) {
        Ok(result) => result,
        Err(err) => {
            let msg = if let Some(s) = err.downcast_ref::<&str>() {
                (*s).to_string()
            } else if let Some(s) = err.downcast_ref::<String>() {
                s.clone()
            } else {
                "unknown internal panic".to_string()
            };
            Err(format!("PdfCraft engine panic in {context}: {msg}"))
        }
    }
}

fn worker_main(automation: Automation, root: PathBuf, mut rx: tokio::sync::mpsc::Receiver<Cmd>) {
    let mut state = Runtime {
        automation,
        root,
        docs: HashMap::new(),
        pending_saves: HashMap::new(),
        next_document: 1,
        next_save_token: 1,
        next_file: 1,
    };
    while let Some(command) = rx.blocking_recv() {
        match command {
            Cmd::Open(request, reply) => {
                if reply.is_closed() {
                    continue;
                }
                let result = catch_panic(|| open_document(&mut state, request), "open");
                let _ = reply.send(result);
            }
            Cmd::Status(handle, reply) => {
                let result = catch_panic(|| document_status(&state, handle), "document status");
                let _ = reply.send(result);
            }
            Cmd::PageSize(handle, page, reply) => {
                let result = catch_panic(|| page_size(&state, handle, page), "page size");
                let _ = reply.send(result);
            }
            Cmd::Render(handle, page, dpi, reply) => {
                let result = catch_panic(|| render_page(&mut state, handle, page, dpi), "render");
                let _ = reply.send(result);
            }
            Cmd::Catalog(reply) => {
                let _ = reply.send(Ok(tool_catalog()));
            }
            Cmd::Execute(handle, tool, args, reply) => {
                if reply.is_closed() {
                    continue;
                }
                let result = catch_panic(
                    || execute_tool(&mut state, handle, &tool, &args),
                    "execute tool",
                );
                let _ = reply.send(result);
            }
            Cmd::SaveSnapshot(handle, for_export, reply) => {
                let result = catch_panic(
                    || save_snapshot(&mut state, handle, for_export),
                    "save snapshot",
                );
                let _ = reply.send(result);
            }
            Cmd::CommitSave(handle, token, reply) => {
                let result = catch_panic(|| commit_save(&mut state, handle, token), "commit save");
                let _ = reply.send(result);
            }
            Cmd::CancelSave(handle, token, reply) => {
                let result = catch_panic(|| cancel_save(&mut state, handle, token), "cancel save");
                let _ = reply.send(result);
            }
            Cmd::StageFile(name, bytes, reply) => {
                let result = catch_panic(|| stage_file(&mut state, &name, &bytes), "stage file");
                let _ = reply.send(result);
            }
            Cmd::ReadOutput(path, reply) => {
                let result = catch_panic(|| read_output(&state, &path), "read output");
                let _ = reply.send(result);
            }
            Cmd::Close(handle, discard, reply) => {
                let result = catch_panic(|| close_document(&mut state, handle, discard), "close");
                let _ = reply.send(result);
            }
        }
    }
}

fn open_document(state: &mut Runtime, request: OpenReq) -> Result<u32, String> {
    let handle = state.next_document;
    let following = handle
        .checked_add(1)
        .ok_or_else(|| "mobile document handle limit reached".to_owned())?;
    let mut staging_name = safe_file_name(&request.name);
    if staging_name.len() > 4 && !staging_name.to_ascii_lowercase().ends_with(".pdf") {
        staging_name.push_str(".pdf");
    }
    let imports = state.root.join("imports");
    fs::create_dir_all(&imports).map_err(|error| format!("create import folder: {error}"))?;
    let directory = tempfile::Builder::new()
        .prefix("document-")
        .tempdir_in(&imports)
        .map_err(|error| format!("create private document folder: {error}"))?;
    let absolute = directory.path().join(staging_name);
    let staging_path = absolute
        .strip_prefix(&state.root)
        .expect("document folder is inside the workspace")
        .to_string_lossy()
        .into_owned();
    fs::write(&absolute, request.bytes).map_err(|error| format!("stage PDF: {error}"))?;
    let mut args = json!({ "path": staging_path });
    if let Some(password) = request.password {
        args["password"] = Value::String(password);
    }
    let contents = match state.automation.call("doc_open", &args) {
        Ok(contents) => contents,
        Err(error) => {
            let _ = fs::remove_file(absolute);
            return Err(error.to_string());
        }
    };
    let summary = contents
        .into_iter()
        .find_map(|content| match content {
            Content::Json(value) => Some(value),
            Content::Png { .. } => None,
        })
        .ok_or_else(|| "PdfCraft returned no document summary".to_owned())?;
    let automation_id = summary["doc"]
        .as_u64()
        .ok_or_else(|| "PdfCraft returned an invalid document id".to_owned())?;
    let page_count = summary["pages"]
        .as_u64()
        .and_then(|pages| u32::try_from(pages).ok())
        .ok_or_else(|| "document has too many pages for the mobile bridge".to_owned())?;
    if page_count == 0 {
        let _ = state.automation.call(
            "doc_close",
            &json!({"doc":automation_id,"discard_changes":true}),
        );
        let _ = fs::remove_file(absolute);
        return Err("the PDF contains no pages".to_owned());
    }
    state.next_document = following;
    state.docs.insert(
        handle,
        MobileDoc {
            automation_id,
            staging_path,
            directory,
            awaiting_external_save: false,
        },
    );
    Ok(handle)
}

fn document_status(state: &Runtime, handle: u32) -> Result<DocumentStatus, String> {
    let doc = state
        .docs
        .get(&handle)
        .ok_or_else(|| "unknown document".to_owned())?;
    let document = state
        .automation
        .session()
        .get(DocId(doc.automation_id))
        .ok_or_else(|| "document is not open in the engine".to_owned())?;
    let page_count = u32::try_from(document.info.pages.len())
        .map_err(|_| "document has too many pages for the mobile bridge".to_owned())?;
    Ok(DocumentStatus {
        page_count,
        dirty: document.dirty || doc.awaiting_external_save,
        editable: document.editable(),
        can_undo: document.can_undo().unwrap_or_default().to_owned(),
        can_redo: document.can_redo().unwrap_or_default().to_owned(),
    })
}

fn page_size(state: &Runtime, handle: u32, page_1based: u32) -> Result<PageSize, String> {
    let doc = state
        .docs
        .get(&handle)
        .ok_or_else(|| "unknown document".to_owned())?;
    let document = state
        .automation
        .session()
        .get(DocId(doc.automation_id))
        .ok_or_else(|| "document is not open in the engine".to_owned())?;
    let page_index = checked_page(page_1based, document.info.pages.len())?;
    let page = document
        .info
        .pages
        .get(page_index)
        .ok_or_else(|| "page out of range".to_owned())?;
    Ok(PageSize {
        width: page.width,
        height: page.height,
    })
}

fn render_page(
    state: &mut Runtime,
    handle: u32,
    page_1based: u32,
    dpi: u32,
) -> Result<Vec<u8>, String> {
    if !(1..=600).contains(&dpi) {
        return Err("dpi must be between 1 and 600".to_owned());
    }
    let doc = state
        .docs
        .get(&handle)
        .ok_or_else(|| "unknown document".to_owned())?;
    let contents = state
        .automation
        .call(
            "page_render",
            &json!({"doc":doc.automation_id,"page":page_1based,"dpi":dpi}),
        )
        .map_err(|error| error.to_string())?;
    contents
        .into_iter()
        .find_map(|content| match content {
            Content::Png { data, .. } => Some(data),
            Content::Json(_) => None,
        })
        .ok_or_else(|| "PdfCraft returned no rendered page".to_owned())
}

fn execute_tool(
    state: &mut Runtime,
    handle: u32,
    tool: &str,
    arguments_json: &str,
) -> Result<OperationResponse, String> {
    let definition = TOOL_DEFINITIONS
        .iter()
        .find(|definition| definition.name == tool && mobile_tool(definition))
        .ok_or_else(|| {
            format!("operation {tool:?} is not exposed by the mobile operation catalog")
        })?;
    let mut arguments: Value = serde_json::from_str(arguments_json)
        .map_err(|error| format!("invalid operation arguments: {error}"))?;
    let object = arguments
        .as_object_mut()
        .ok_or_else(|| "operation arguments must be a JSON object".to_owned())?;
    let document_arg = current_document_arg(definition);
    if let Some(arg) = document_arg {
        let doc = state
            .docs
            .get(&handle)
            .ok_or_else(|| "unknown document".to_owned())?;
        if tool == "doc_rename" && doc.awaiting_external_save {
            return Err("Save the document before renaming its working copy.".to_owned());
        }
        object.insert(arg.to_owned(), json!(doc.automation_id));
    }

    // The Android print service supplies its own picker and media list in Flutter.
    #[cfg(target_os = "android")]
    if tool == "printer_papers" {
        return Err(
            "Use the Android print dialog to choose a printer and view its supported paper sizes."
                .to_owned(),
        );
    }

    let output = match tool {
        "doc_create" | "doc_open_revision" | "link_open" => {
            let out = match object.remove("out") {
                Some(Value::String(path)) => path,
                Some(_) => return Err("out must be a workspace-relative file name".to_owned()),
                None => output_pdf_path(state, tool)?,
            };
            Some(out)
        }
        "doc_combine" | "doc_create_multiple" | "page_extract" => {
            let separate = object.get("separate") == Some(&Value::Bool(true))
                || object.get("mode").and_then(Value::as_str) == Some("separate");
            if !separate && !object.contains_key("out") {
                object.insert("out".to_owned(), json!(output_pdf_path(state, tool)?));
            }
            object.insert("open".to_owned(), Value::Bool(false));
            None
        }
        _ => None,
    };
    // Android's picker grants one file at a time. Place the selected companion at its link's
    // relative name while the upstream GoToR operation resolves the destination.
    let _link_alias = if tool == "link_open"
        && let Some(file) = object.remove("linked_file")
    {
        let path = file
            .as_str()
            .ok_or_else(|| "linked_file must be a staged PDF path".to_owned())?;
        Some(stage_link_target(state, handle, object, path)?)
    } else {
        None
    };
    let second_arg =
        second_pdf_arg(tool).filter(|key| *key != "to_doc" || object.contains_key(*key));
    let target_output = if tool == "content_copy" && second_arg.is_some() {
        Some(output_pdf_path(state, tool)?)
    } else {
        None
    };
    let mut contents = if let Some(source_arg) = second_arg {
        call_with_second_pdf(
            &mut state.automation,
            tool,
            arguments,
            source_arg,
            target_output.as_deref(),
        )?
    } else {
        state
            .automation
            .call(tool, &arguments)
            .map_err(|error| error.to_string())?
    };
    if let Some(path) = output {
        // These operations create a separate automation document, while the viewer owns only
        // the current one. Deliver the new document through the same output flow as an export.
        let result = result_json_mut(&mut contents)?;
        let id = result["doc"]
            .as_u64()
            .or_else(|| result["document"]["doc"].as_u64())
            .ok_or_else(|| format!("{tool}: missing generated document"))?;
        let saved = write_document_copy(&state.automation, id, &path);
        let closed = close_temporary(&mut state.automation, id);
        saved?;
        closed?;
        if let Some(payload) = result.as_object_mut() {
            payload.remove("doc");
            payload.remove("document");
            payload.insert("path".to_owned(), json!(path));
        }
    } else if tool == "doc_rename" {
        let path = result_json_mut(&mut contents)?["path"]
            .as_str()
            .ok_or_else(|| "rename returned no path".to_owned())?;
        let relative = Path::new(path)
            .strip_prefix(&state.root)
            .map_err(|_| "renamed file outside workspace".to_owned())?;
        state
            .docs
            .get_mut(&handle)
            .ok_or_else(|| "unknown document".to_owned())?
            .staging_path = relative.to_string_lossy().into_owned();
    }

    let status = if document_arg.is_some() {
        document_status(state, handle)?
    } else {
        DocumentStatus::default()
    };
    Ok(OperationResponse {
        contents: operation_contents(contents, &state.root),
        status,
    })
}

fn stage_link_target(
    state: &Runtime,
    handle: u32,
    args: &serde_json::Map<String, Value>,
    picked: &str,
) -> Result<tempfile::TempPath, String> {
    let doc = state
        .docs
        .get(&handle)
        .ok_or_else(|| "unknown document".to_owned())?;
    let loaded = state
        .automation
        .session()
        .get(DocId(doc.automation_id))
        .ok_or_else(|| "source document is no longer open".to_owned())?;
    let link = loaded
        .info
        .links
        .iter()
        .find(|link| {
            args.get("page").and_then(Value::as_u64) == Some(link.page as u64 + 1)
                && args.get("index").and_then(Value::as_u64) == Some(link.index as u64 + 1)
        })
        .ok_or_else(|| "pick a link from the page's link list".to_owned())?;
    let pdfcraft_render::LinkTarget::RemoteGoTo { file, .. } = &link.target else {
        return Err("the selected link does not point to a local PDF".to_owned());
    };
    let source = state.root.join(&doc.staging_path);
    let target = pdfcraft_engine::resolve_remote_document_path(Some(&source), file)
        .map_err(|error| error.to_string())?;
    let relative = target
        .strip_prefix(doc.directory.path())
        .map_err(|_| "the link must be relative to this PDF's folder".to_owned())?;
    if !relative
        .components()
        .all(|c| matches!(c, Component::Normal(_)))
        || relative.file_name().is_none()
    {
        return Err("the link must name a file within the document folder".to_owned());
    }
    let picked = state
        .root
        .join(picked)
        .canonicalize()
        .map_err(|error| format!("resolve selected PDF: {error}"))?;
    if !picked.starts_with(&state.root) || !picked.is_file() {
        return Err("select a PDF imported into the app workspace".to_owned());
    }
    let mut dir = doc.directory.path().to_path_buf();
    for part in relative.parent().into_iter().flat_map(Path::components) {
        dir.push(part.as_os_str());
        match fs::create_dir(&dir) {
            Ok(()) => {}
            Err(err)
                if err.kind() == std::io::ErrorKind::AlreadyExists
                    && dir.symlink_metadata().is_ok_and(|meta| meta.is_dir()) => {}
            Err(err) => return Err(format!("prepare linked PDF folder: {err}")),
        }
    }
    // hard_link atomically refuses to overwrite an existing document and avoids a second copy.
    fs::hard_link(picked, &target).map_err(|error| format!("stage linked PDF: {error}"))?;
    tempfile::TempPath::try_from_path(target).map_err(|error| error.to_string())
}

fn output_pdf_path(state: &mut Runtime, tool: &str) -> Result<String, String> {
    loop {
        let id = state.next_file;
        state.next_file = id
            .checked_add(1)
            .ok_or_else(|| "staged file limit reached".to_owned())?;
        let path = format!("outputs/{tool}-{id}.pdf");
        if !state.root.join(&path).exists() {
            return Ok(path);
        }
    }
}

fn result_json_mut(contents: &mut [Content]) -> Result<&mut Value, String> {
    contents
        .iter_mut()
        .find_map(|content| match content {
            Content::Json(value) => Some(value),
            Content::Png { .. } => None,
        })
        .ok_or_else(|| "PdfCraft returned no document summary".to_owned())
}

fn write_document_copy(automation: &Automation, id: u64, path: &str) -> Result<(), String> {
    let bytes = automation
        .session()
        .save_bytes(DocId(id))
        .map_err(|error| error.to_string())?;
    automation
        .write_output(path, &bytes)
        .map(|_| ())
        .map_err(|error| error.to_string())
}

fn close_temporary(automation: &mut Automation, id: u64) -> Result<(), String> {
    automation
        .call("doc_close", &json!({"doc":id, "discard_changes":true}))
        .map(|_| ())
        .map_err(|error| error.to_string())
}

fn call_with_second_pdf(
    automation: &mut Automation,
    tool: &str,
    mut args: Value,
    source_arg: &str,
    target_output: Option<&str>,
) -> Result<Vec<Content>, String> {
    let path = args[source_arg]
        .as_str()
        .ok_or_else(|| format!("{source_arg} must be a staged PDF file path"))?;
    let mut opened = automation
        .call("doc_open", &json!({"path":path}))
        .map_err(|error| error.to_string())?;
    let id = result_json_mut(&mut opened)?["doc"]
        .as_u64()
        .ok_or_else(|| "second PDF has no document ID".to_owned())?;
    args[source_arg] = json!(id);
    let result = automation
        .call(tool, &args)
        .map_err(|error| error.to_string())
        .and_then(|mut contents| {
            if let Some(out) = target_output {
                write_document_copy(automation, id, out)?;
                result_json_mut(&mut contents)?["path"] = json!(out);
            }
            Ok(contents)
        });
    let closed = close_temporary(automation, id);
    let contents = result?;
    closed?;
    Ok(contents)
}

fn operation_contents(contents: Vec<Content>, root: &Path) -> Vec<OperationContent> {
    contents
        .into_iter()
        .map(|content| match content {
            Content::Json(mut value) => {
                relativize_workspace_paths(&mut value, root);
                OperationContent {
                    json: value.to_string(),
                    png: Vec::new(),
                    width: 0,
                    height: 0,
                }
            }
            Content::Png {
                data,
                width,
                height,
            } => OperationContent {
                json: String::new(),
                png: data,
                width,
                height,
            },
        })
        .collect()
}

/// Strip the confined workspace root from any path strings inside tool JSON so
/// callers receive workspace-relative paths (`outputs/...`, `imports/...`) and
/// host/device filesystem roots never cross the bridge.
fn relativize_workspace_paths(value: &mut Value, root: &Path) {
    match value {
        Value::String(text) => {
            if let Ok(relative) = Path::new(text.as_str()).strip_prefix(root)
                && !relative.as_os_str().is_empty()
            {
                *text = relative.to_string_lossy().replace('\\', "/");
            }
        }
        Value::Array(items) => {
            for item in items {
                relativize_workspace_paths(item, root);
            }
        }
        Value::Object(map) => {
            for entry in map.values_mut() {
                relativize_workspace_paths(entry, root);
            }
        }
        Value::Null | Value::Bool(_) | Value::Number(_) => {}
    }
}

fn save_snapshot(
    state: &mut Runtime,
    handle: u32,
    for_export: bool,
) -> Result<SaveSnapshot, String> {
    let doc = state
        .docs
        .get_mut(&handle)
        .ok_or_else(|| "unknown document".to_owned())?;
    let automation_id = doc.automation_id;
    let id = DocId(automation_id);
    if for_export {
        // Run WillSave in this document's retained script realm before handing bytes to Android.
        // The engine has saved its private working file; it is still unsaved externally until the
        // picker confirms. Recovery, print and edit-preview snapshots never run this event.
        let previous = state
            .automation
            .session()
            .get(id)
            .ok_or_else(|| "document is no longer open".to_owned())?;
        let previous_bytes = previous.saved_bytes();
        let previously_dirty = previous.dirty;
        state
            .automation
            .call("doc_save", &json!({"doc":automation_id}))
            .map_err(|error| error.to_string())?;
        let saved = state
            .automation
            .session()
            .get(id)
            .ok_or_else(|| "saved document is no longer open".to_owned())?
            .saved_bytes();
        doc.awaiting_external_save |= previously_dirty
            || (!std::sync::Arc::ptr_eq(&saved, &previous_bytes) && saved != previous_bytes);
    }
    let document = state
        .automation
        .session()
        .get(id)
        .ok_or_else(|| "document is not open in the engine".to_owned())?;
    let generation = document.edit_generation();
    let bytes = if for_export {
        document.saved_bytes()
    } else {
        state
            .automation
            .session()
            .save_bytes(id)
            .map_err(|error| error.to_string())?
    };
    let token = state.next_save_token;
    state.next_save_token = token
        .checked_add(1)
        .ok_or_else(|| "save token limit reached".to_owned())?;
    state.pending_saves.insert(
        token,
        PendingSave {
            handle,
            automation_id,
            generation,
            prepared_for_export: for_export,
        },
    );
    Ok(SaveSnapshot {
        token,
        bytes: bytes.as_ref().clone(),
    })
}

fn commit_save(state: &mut Runtime, handle: u32, token: u32) -> Result<(), String> {
    let pending = *state
        .pending_saves
        .get(&token)
        .ok_or_else(|| "save snapshot is expired".to_owned())?;
    if pending.handle != handle {
        return Err("save snapshot belongs to another document".to_owned());
    }
    let doc = state
        .automation
        .session()
        .get(DocId(pending.automation_id))
        .ok_or_else(|| "document is no longer open".to_owned())?;
    if doc.edit_generation() != pending.generation {
        state.pending_saves.remove(&token);
        return Err("document changed during Save As; save the latest version again".to_owned());
    }
    let mobile_doc = state
        .docs
        .get_mut(&handle)
        .ok_or_else(|| "unknown document".to_owned())?;
    if !pending.prepared_for_export {
        // Compatibility for callers that still commit a plain snapshot.
        state
            .automation
            .call(
                "doc_save",
                &json!({"doc":pending.automation_id,"path":mobile_doc.staging_path}),
            )
            .map_err(|error| {
                format!(
                    "external Save As succeeded, but updating engine save state failed: {error}"
                )
            })?;
    }
    mobile_doc.awaiting_external_save = false;
    state.pending_saves.remove(&token);
    Ok(())
}

fn cancel_save(state: &mut Runtime, handle: u32, token: u32) -> Result<(), String> {
    match state.pending_saves.get(&token) {
        Some(pending) if pending.handle == handle => {
            state.pending_saves.remove(&token);
            Ok(())
        }
        _ => Err("save snapshot is expired or belongs to another document".to_owned()),
    }
}

fn stage_file(state: &mut Runtime, name: &str, bytes: &[u8]) -> Result<String, String> {
    let file_id = state.next_file;
    state.next_file = file_id
        .checked_add(1)
        .ok_or_else(|| "staged file limit reached".to_owned())?;
    let safe_name = safe_file_name(name);
    let relative = format!("imports/asset-{file_id}-{safe_name}");
    let target = state.root.join(&relative);
    if let Some(parent) = target.parent() {
        fs::create_dir_all(parent).map_err(|error| format!("create import folder: {error}"))?;
    }
    fs::write(&target, bytes).map_err(|error| format!("stage supporting file: {error}"))?;
    Ok(relative)
}

fn safe_file_name(name: &str) -> String {
    let normalized = name.replace('\\', "/");
    let base = normalized.rsplit('/').next().unwrap_or("file");
    let safe: String = base
        .chars()
        .take(80)
        .map(|ch| {
            if ch.is_ascii_alphanumeric() || matches!(ch, '.' | '-' | '_') {
                ch
            } else {
                '_'
            }
        })
        .collect();
    if safe.is_empty() || safe == "." || safe == ".." {
        "file".to_owned()
    } else {
        safe
    }
}

fn read_output(state: &Runtime, relative: &str) -> Result<Vec<u8>, String> {
    let path = Path::new(relative);
    if !path.is_absolute()
        && path
            .components()
            .any(|component| !matches!(component, Component::Normal(_)))
    {
        return Err("output path must stay inside the app workspace".to_owned());
    }
    let candidate = if path.is_absolute() {
        path.to_path_buf()
    } else {
        state.root.join(path)
    };
    let absolute = candidate
        .canonicalize()
        .map_err(|error| format!("resolve output: {error}"))?;
    if !absolute.starts_with(&state.root) {
        return Err("output path is outside the app workspace".to_owned());
    }
    fs::read(&absolute).map_err(|error| format!("read output: {error}"))
}

fn close_document(state: &mut Runtime, handle: u32, discard_changes: bool) -> Result<(), String> {
    let doc = state
        .docs
        .get(&handle)
        .ok_or_else(|| "unknown document".to_owned())?;
    if doc.awaiting_external_save && !discard_changes {
        return Err("the document has changes that have not been saved outside the app".to_owned());
    }
    let result = state.automation.call(
        "doc_close",
        &json!({"doc":doc.automation_id,"discard_changes":discard_changes}),
    );
    result.map_err(|error| error.to_string())?;
    state.docs.remove(&handle);
    state
        .pending_saves
        .retain(|_, pending| pending.handle != handle);
    Ok(())
}

fn checked_page(page_1based: u32, page_count: usize) -> Result<usize, String> {
    let index = (page_1based as usize)
        .checked_sub(1)
        .ok_or_else(|| "pages are 1-based".to_owned())?;
    if index >= page_count {
        return Err(format!(
            "page {page_1based} is out of range (1-{page_count})"
        ));
    }
    Ok(index)
}

fn tool_catalog() -> Vec<OperationInfo> {
    TOOL_DEFINITIONS
        .iter()
        .filter(|tool| mobile_tool(tool))
        .map(operation_info)
        .collect()
}

fn current_document_arg(tool: &ToolDef) -> Option<&'static str> {
    match tool.name {
        "accessibility_review_record" | "accessibility_review_html" => Some("after"),
        _ if tool.input_schema["properties"]["doc"].is_object() => Some("doc"),
        _ => None,
    }
}

fn second_pdf_arg(name: &str) -> Option<&'static str> {
    match name {
        "doc_compare" | "doc_compare_mark" | "doc_compare_report" => Some("other"),
        "bookmark_copy" => Some("from"),
        "content_copy" => Some("to_doc"),
        "accessibility_review_record" | "accessibility_review_html" => Some("before"),
        _ => None,
    }
}

fn mobile_tool(tool: &ToolDef) -> bool {
    match tool.name {
        "doc_open" | "doc_list" | "doc_close" | "doc_save" | "command_run" | "command_batch" => {
            false
        }
        "doc_combine"
        | "doc_create"
        | "doc_create_multiple"
        | "fill_sign_date_format"
        | "ocr_recognize_files"
        | "ocr_status"
        | "doc_batch"
        | "doc_bates_multi"
        | "ocr_dictionary"
        | "print_color_profiles"
        | "printer_papers"
        | "text_font_files" => true,
        _ => current_document_arg(tool).is_some(),
    }
}

fn operation_info(tool: &ToolDef) -> OperationInfo {
    let current_arg = current_document_arg(tool);
    let requires_document = current_arg.is_some();
    let mut schema = tool.input_schema.clone();
    if let Some(arg) = current_arg {
        if let Some(properties) = schema["properties"].as_object_mut() {
            properties.remove(arg);
        }
        if let Some(required) = schema["required"].as_array_mut() {
            required.retain(|entry| entry.as_str() != Some(arg));
        }
    }
    if let Some(key) = second_pdf_arg(tool.name) {
        schema["properties"][key] = json!({"type":"string","format":"pdf-file","description":"Choose a PDF file to import."});
    }
    if tool.name == "link_open" {
        schema["properties"]["linked_file"] = json!({"type":"string","format":"pdf-file","description":"Import the target PDF of a relative file link from this PDF's folder."});
    }
    if cfg!(target_os = "android") && tool.name == "printer_papers" {
        schema["properties"] = json!({});
        schema["required"] = json!([]);
    }
    if matches!(tool.name, "doc_create" | "doc_open_revision" | "link_open") {
        schema["properties"]["out"] =
            json!({"type":"string","description":"Output PDF path in the app workspace."});
    }
    if matches!(
        tool.name,
        "doc_combine" | "doc_create_multiple" | "page_extract"
    ) && let Some(properties) = schema["properties"].as_object_mut()
    {
        properties.remove("open");
    }
    OperationInfo {
        id: tool.name.to_owned(),
        title: match tool.name {
            "printer_papers" if cfg!(target_os = "android") => "Android paper sizes",
            "doc_rename" => "Rename the app’s working copy",
            _ => tool.title,
        }.to_owned(),
        description: match tool.name {
            "doc_rename" => "Rename the copy of the open PDF in the app workspace. Use Save As to store it under the new name.",
            "printer_papers" if cfg!(target_os = "android") => "Browse Android standard media sizes. Choose a printer in the print dialog to see its supported media.",
            "doc_create" => "Create a PDF from blank pages, imported images or text and save the resulting PDF.",
            "link_open" => "Resolve a local PDF link inside the app workspace and return a PDF copy with its destination details.",
            "doc_open_revision" => "Export a saved revision of the open document as a PDF.",
            "text_font_files" => "List font files imported into the app workspace.",
            "print_color_profiles" => "List ICC colour profiles imported into the app workspace.",
            _ => tool.description,
        }.to_owned(),
        input_schema_json: schema.to_string(),
        read_only: tool.read_only,
        destructive: tool.destructive,
        command_id: tool.command.unwrap_or_default().to_owned(),
        requires_document,
    }
}
