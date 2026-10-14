use std::collections::HashMap;
use std::fs;
use std::path::{Component, Path, PathBuf};
use std::thread;
use std::time::Duration;

use flutter_rust_bridge::frb;
use pdfcraft_automation::{Automation, Content, ToolDef, tools};
use pdfcraft_engine::DocId;
use serde_json::{Value, json};
use tokio::sync::oneshot;

const COMMAND_QUEUE_CAPACITY: usize = 2;
const OP_TIMEOUT: Duration = Duration::from_secs(120);
const SAVE_TIMEOUT: Duration = Duration::from_secs(180);

struct MobileDoc {
    automation_id: u64,
    staging_path: String,
}

#[derive(Clone, Copy)]
struct PendingSave {
    handle: u32,
    automation_id: u64,
    generation: u64,
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
    SaveSnapshot(u32, oneshot::Sender<Result<SaveSnapshot, String>>),
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
            Cmd::SaveSnapshot(handle, reply),
            rx,
            SAVE_TIMEOUT,
            "prepare save",
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
        tokio::time::timeout(timeout, async {
            self.tx.send(command).await.map_err(worker_gone)?;
            reply.await.map_err(worker_gone)?
        })
        .await
        .map_err(|_| format!("engine is busy: {operation} timed out"))?
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
                let result = open_document(&mut state, request);
                let _ = reply.send(result);
            }
            Cmd::Status(handle, reply) => {
                let _ = reply.send(document_status(&state, handle));
            }
            Cmd::PageSize(handle, page, reply) => {
                let _ = reply.send(page_size(&state, handle, page));
            }
            Cmd::Render(handle, page, dpi, reply) => {
                let _ = reply.send(render_page(&mut state, handle, page, dpi));
            }
            Cmd::Catalog(reply) => {
                let _ = reply.send(Ok(tool_catalog()));
            }
            Cmd::Execute(handle, tool, args, reply) => {
                if reply.is_closed() {
                    continue;
                }
                let _ = reply.send(execute_tool(&mut state, handle, &tool, &args));
            }
            Cmd::SaveSnapshot(handle, reply) => {
                let _ = reply.send(save_snapshot(&mut state, handle));
            }
            Cmd::CommitSave(handle, token, reply) => {
                let _ = reply.send(commit_save(&mut state, handle, token));
            }
            Cmd::CancelSave(handle, token, reply) => {
                let _ = reply.send(cancel_save(&mut state, handle, token));
            }
            Cmd::StageFile(name, bytes, reply) => {
                let _ = reply.send(stage_file(&mut state, &name, &bytes));
            }
            Cmd::ReadOutput(path, reply) => {
                let _ = reply.send(read_output(&state, &path));
            }
            Cmd::Close(handle, discard, reply) => {
                let _ = reply.send(close_document(&mut state, handle, discard));
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
    let staging_path = format!("imports/mobile-{handle}-{staging_name}");
    let absolute = state.root.join(&staging_path);
    if let Some(parent) = absolute.parent() {
        fs::create_dir_all(parent).map_err(|error| format!("create import folder: {error}"))?;
    }
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
        dirty: document.dirty,
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
    let definition = tools()
        .into_iter()
        .find(|definition| definition.name == tool && mobile_tool(tool))
        .ok_or_else(|| {
            format!("operation {tool:?} is not exposed by the mobile operation catalog")
        })?;
    let requires_document = definition.input_schema["properties"]["doc"].is_object();
    if !requires_document
        && !matches!(
            tool,
            "doc_combine"
                | "doc_create"
                | "doc_create_multiple"
                | "fill_sign_date_format"
                | "ocr_recognize_files"
                | "ocr_status"
        )
    {
        return Err(format!(
            "operation {tool:?} is not exposed by the mobile operation catalog"
        ));
    }
    let mut arguments: Value = serde_json::from_str(arguments_json)
        .map_err(|error| format!("invalid operation arguments: {error}"))?;
    let object = arguments
        .as_object_mut()
        .ok_or_else(|| "operation arguments must be a JSON object".to_owned())?;
    if matches!(
        tool,
        "doc_compare" | "doc_compare_mark" | "doc_compare_report"
    ) {
        return compare_with_file(state, handle, tool, object);
    }
    if tool == "doc_create" {
        return create_blank(state, object);
    }
    if requires_document {
        let doc = state
            .docs
            .get(&handle)
            .ok_or_else(|| "unknown document".to_owned())?;
        object.insert("doc".to_owned(), json!(doc.automation_id));
    } else if tool == "doc_combine" {
        // A combined document is exported through the mobile file picker; don't create a
        // second automation document that the current Flutter viewer cannot own yet.
        let file_id = state.next_file;
        state.next_file = file_id
            .checked_add(1)
            .ok_or_else(|| "staged file limit reached".to_owned())?;
        object
            .entry("out")
            .or_insert_with(|| json!(format!("combined-mobile-{file_id}.pdf")));
        object.entry("open").or_insert(Value::Bool(false));
    } else if tool == "doc_create_multiple" {
        // Mobile owns one viewer document at a time; create a file output and
        // let Flutter deliver it through Save As instead of opening a hidden
        // Automation document in the background.
        let file_id = state.next_file;
        state.next_file = file_id
            .checked_add(1)
            .ok_or_else(|| "staged file limit reached".to_owned())?;
        object
            .entry("out")
            .or_insert_with(|| json!(format!("created-mobile-{file_id}.pdf")));
        object.entry("open").or_insert(Value::Bool(false));
    }
    let contents = state
        .automation
        .call(tool, &arguments)
        .map_err(|error| error.to_string())?;
    let contents = operation_contents(contents, &state.root);
    let status = if requires_document {
        document_status(state, handle)?
    } else {
        DocumentStatus {
            page_count: 0,
            dirty: false,
            editable: false,
            can_undo: String::new(),
            can_redo: String::new(),
        }
    };
    Ok(OperationResponse { contents, status })
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

/// Create a blank PDF without opening a second viewer document: the upstream
/// tool opens a new automation document, so its bytes are written to an
/// output file and the temporary document is closed again. Only blank
/// creation is exposed; images/text go through the staged-file flows.
fn create_blank(
    state: &mut Runtime,
    object: &mut serde_json::Map<String, Value>,
) -> Result<OperationResponse, String> {
    if object.get("from").and_then(Value::as_str) != Some("blank") {
        return Err("mobile blank-PDF creation only supports a blank document".to_owned());
    }
    let out = object
        .get("out")
        .and_then(Value::as_str)
        .map(str::to_owned)
        .unwrap_or_else(|| "outputs/blank.pdf".to_owned());
    let out_path = Path::new(&out);
    if out_path.is_absolute()
        || out_path
            .components()
            .any(|component| !matches!(component, Component::Normal(_)))
    {
        return Err("output path must stay inside the app workspace".to_owned());
    }
    let mut create_args = serde_json::Map::new();
    create_args.insert("from".to_owned(), Value::String("blank".to_owned()));
    if let Some(pages) = object.get("pages").and_then(Value::as_i64) {
        create_args.insert("pages".to_owned(), Value::Number(pages.into()));
    }
    let created = state
        .automation
        .call("doc_create", &Value::Object(create_args))
        .map_err(|error| error.to_string())?;
    let created_id = created
        .iter()
        .find_map(|content| match content {
            Content::Json(value) => value["doc"].as_u64(),
            Content::Png { .. } => None,
        })
        .ok_or_else(|| "could not create the blank document".to_owned())?;
    let bytes = state
        .automation
        .session()
        .save_bytes(DocId(created_id))
        .map_err(|error| error.to_string())?;
    let target = state.root.join(out_path);
    if let Some(parent) = target.parent() {
        fs::create_dir_all(parent).map_err(|error| format!("create output folder: {error}"))?;
    }
    fs::write(&target, bytes.as_ref()).map_err(|error| format!("write blank PDF: {error}"))?;
    let _ = state.automation.call(
        "doc_close",
        &json!({"doc": created_id, "discard_changes": true}),
    );
    Ok(OperationResponse {
        contents: vec![OperationContent {
            json: json!({"path": out}).to_string(),
            png: Vec::new(),
            width: 0,
            height: 0,
        }],
        status: DocumentStatus {
            page_count: 0,
            dirty: false,
            editable: false,
            can_undo: String::new(),
            can_redo: String::new(),
        },
    })
}

/// Compare the open document against a workspace file: the upstream tool
/// takes an open document id, so the file is opened temporarily and closed
/// afterwards without touching the user's document list.
fn compare_with_file(
    state: &mut Runtime,
    handle: u32,
    tool: &str,
    object: &mut serde_json::Map<String, Value>,
) -> Result<OperationResponse, String> {
    let doc = state
        .docs
        .get(&handle)
        .ok_or_else(|| "unknown document".to_owned())?;
    let other_path = object
        .get("other")
        .and_then(|value| value.as_str())
        .ok_or_else(|| "compare needs the other file's workspace path".to_owned())?
        .to_owned();
    let opened = state
        .automation
        .call("doc_open", &json!({"path": other_path}))
        .map_err(|error| error.to_string())?;
    let other_id = opened
        .iter()
        .find_map(|content| match content {
            Content::Json(value) => value["doc"].as_u64(),
            Content::Png { .. } => None,
        })
        .ok_or_else(|| "could not open the comparison file".to_owned())?;
    let mut arguments = json!({"doc": doc.automation_id, "other": other_id});
    if tool == "doc_compare" {
        if let Some(limit) = object.get("limit") {
            arguments["limit"] = limit.clone();
        }
        if let Some(visual) = object.get("visual") {
            arguments["visual"] = visual.clone();
        }
    }
    if tool == "doc_compare_report" {
        // The report path stays workspace-relative; the app offers Save As.
        if let Some(path) = object.get("path") {
            arguments["path"] = path.clone();
        }
    }
    let result = state.automation.call(tool, &arguments);
    let _ = state.automation.call(
        "doc_close",
        &json!({"doc": other_id, "discard_changes": true}),
    );
    let contents = result.map_err(|error| error.to_string())?;
    let contents = operation_contents(contents, &state.root);
    let status = document_status(state, handle)?;
    Ok(OperationResponse { contents, status })
}

fn save_snapshot(state: &mut Runtime, handle: u32) -> Result<SaveSnapshot, String> {
    let doc = state
        .docs
        .get(&handle)
        .ok_or_else(|| "unknown document".to_owned())?;
    let automation_id = doc.automation_id;
    let generation = state
        .automation
        .session()
        .get(DocId(automation_id))
        .ok_or_else(|| "document is not open in the engine".to_owned())?
        .edit_generation();
    let bytes = state
        .automation
        .session()
        .save_bytes(DocId(automation_id))
        .map_err(|error| error.to_string())?;
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
    let staging_path = state
        .docs
        .get(&handle)
        .ok_or_else(|| "unknown document".to_owned())?
        .staging_path
        .clone();
    let result = state.automation.call(
        "doc_save",
        &json!({"doc":pending.automation_id,"path":staging_path}),
    );
    result.map_err(|error| {
        format!("external Save As succeeded, but updating engine save state failed: {error}")
    })?;
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
    let result = state.automation.call(
        "doc_close",
        &json!({"doc":doc.automation_id,"discard_changes":discard_changes}),
    );
    result.map_err(|error| error.to_string())?;
    let doc = state
        .docs
        .remove(&handle)
        .ok_or_else(|| "document close raced with another command".to_owned())?;
    state
        .pending_saves
        .retain(|_, pending| pending.handle != handle);
    let staged = state.root.join(doc.staging_path);
    let _ = fs::remove_file(staged);
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
    tools()
        .into_iter()
        .filter(|tool| mobile_tool(tool.name))
        .map(operation_info)
        .collect()
}

fn mobile_tool(name: &str) -> bool {
    !matches!(
        name,
        "doc_open" | "doc_list" | "doc_close" | "doc_save" | "command_run" | "command_batch"
    ) && (tools()
        .iter()
        .any(|tool| tool.name == name && tool.input_schema["properties"]["doc"].is_object())
        || matches!(
            name,
            "doc_combine"
                | "doc_create"
                | "doc_create_multiple"
                | "fill_sign_date_format"
                | "ocr_recognize_files"
                | "ocr_status"
        ))
}

fn operation_info(tool: ToolDef) -> OperationInfo {
    let requires_document = tool.input_schema["properties"]["doc"].is_object();
    let mut schema = tool.input_schema;
    if let Some(properties) = schema["properties"].as_object_mut() {
        properties.remove("doc");
    }
    if let Some(required) = schema["required"].as_array_mut() {
        required.retain(|entry| entry.as_str() != Some("doc"));
    }
    OperationInfo {
        id: tool.name.to_owned(),
        title: tool.title.to_owned(),
        description: tool.description.to_owned(),
        input_schema_json: schema.to_string(),
        read_only: tool.read_only,
        destructive: tool.destructive,
        command_id: tool.command.unwrap_or_default().to_owned(),
        requires_document,
    }
}
