use std::collections::HashMap;
use std::sync::Arc;
use std::thread;
use std::time::Duration;

use flutter_rust_bridge::frb;
use pdfcraft_engine::{DocId, Session};
use pdfcraft_render::{PageRenderer, RenderRequest, RequestKind};
use tokio::sync::oneshot;

/// Rendering timeout for one page (the engine's own watchdog retires stuck workers after 20s;
/// this caps the whole request including queueing).
const RENDER_TIMEOUT: Duration = Duration::from_secs(120);
/// Timeout for engine control operations (open/save/count).
const OP_TIMEOUT: Duration = Duration::from_secs(60);

/// One open document on the worker thread: engine identity + a single-threaded renderer over
/// the document's display bytes (the state the engine exposes via `Document::export_source`).
struct OpenDoc {
    doc_id: DocId,
    page_count: usize,
    /// Displayed size per page, in points (after /Rotate and /UserUnit).
    sizes: Vec<(f32, f32)>,
    renderer: PageRenderer,
}

/// Displayed size of a page, in points.
#[derive(Clone)]
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
    PageCount(u32, oneshot::Sender<Result<u32, String>>),
    PageSize(u32, u32, oneshot::Sender<Result<PageSize, String>>),
    Render(u32, u32, u32, oneshot::Sender<Result<Vec<u8>, String>>),
    Save(u32, oneshot::Sender<Result<Vec<u8>, String>>),
    Close(u32, oneshot::Sender<Result<(), String>>),
}

/// The bridge object handed to Flutter. Owns no PDF state: the engine `Session` (which is not
/// `Sync`) lives on a dedicated worker thread; this handle is just the command channel.
#[frb(opaque)]
pub struct Engine {
    tx: tokio::sync::mpsc::UnboundedSender<Cmd>,
}

#[frb(opaque)]
impl Engine {
    #[frb(sync)]
    pub fn new() -> Self {
        let (tx, mut rx) = tokio::sync::mpsc::unbounded_channel::<Cmd>();
        thread::Builder::new()
            .name("pdfcraft-engine".to_owned())
            .spawn(move || worker_main(&mut rx))
            .expect("spawning the engine worker thread");
        Self { tx }
    }

    /// Open a PDF (`name` is used for titles/labels; `password` for encrypted documents).
    /// Returns a document handle.
    pub async fn open(&self, name: String, bytes: Vec<u8>, password: Option<String>) -> Result<u32, String> {
        let (reply, rx) = oneshot::channel();
        self.tx.send(Cmd::Open(OpenReq { name, bytes, password }, reply)).map_err(dropped)?;
        tokio::time::timeout(OP_TIMEOUT, rx).await.map_err(|_| "engine is busy: open timed out".to_owned())?.map_err(dropped)?
    }

    pub async fn page_count(&self, handle: u32) -> Result<u32, String> {
        let (reply, rx) = oneshot::channel();
        self.tx.send(Cmd::PageCount(handle, reply)).map_err(dropped)?;
        tokio::time::timeout(OP_TIMEOUT, rx).await.map_err(|_| "engine is busy: page_count timed out".to_owned())?.map_err(dropped)?
    }

    pub async fn page_size(&self, handle: u32, page_1based: u32) -> Result<PageSize, String> {
        let (reply, rx) = oneshot::channel();
        self.tx.send(Cmd::PageSize(handle, page_1based, reply)).map_err(dropped)?;
        tokio::time::timeout(OP_TIMEOUT, rx).await.map_err(|_| "engine is busy: page_size timed out".to_owned())?.map_err(dropped)?
    }

    /// Render one page (1-based) to PNG at `dpi`. The render itself runs on the worker thread;
    /// the engine's renderer is panic-guarded and never aborts the process.
    pub async fn render_page_png(&self, handle: u32, page_1based: u32, dpi: u32) -> Result<Vec<u8>, String> {
        let (reply, rx) = oneshot::channel();
        self.tx.send(Cmd::Render(handle, page_1based, dpi, reply)).map_err(dropped)?;
        tokio::time::timeout(RENDER_TIMEOUT, rx)
            .await
            .map_err(|_| "render timed out after 120s".to_owned())?
            .map_err(dropped)?
    }

    /// The working file the engine would save right now (incremental write over the original
    /// bytes; unsaved edits are included).
    pub async fn save(&self, handle: u32) -> Result<Vec<u8>, String> {
        let (reply, rx) = oneshot::channel();
        self.tx.send(Cmd::Save(handle, reply)).map_err(dropped)?;
        tokio::time::timeout(OP_TIMEOUT, rx).await.map_err(|_| "engine is busy: save timed out".to_owned())?.map_err(dropped)?
    }

    /// Drop the document locally. (The engine session keeps its parsed state until process end;
    /// a session-level close is future work.)
    pub async fn close(&self, handle: u32) -> Result<(), String> {
        let (reply, rx) = oneshot::channel();
        self.tx.send(Cmd::Close(handle, reply)).map_err(dropped)?;
        tokio::time::timeout(OP_TIMEOUT, rx).await.map_err(|_| "engine is busy: close timed out".to_owned())?.map_err(dropped)?
    }
}

fn dropped<T>(_: T) -> String {
    "engine worker thread is gone".to_owned()
}

fn index(page_1based: u32, page_count: usize) -> Result<usize, String> {
    let index = (page_1based as usize)
        .checked_sub(1)
        .ok_or_else(|| "page numbers are 1-based".to_owned())?;
    if index >= page_count {
        return Err(format!("page {page_1based} is out of range (1-{page_count})"));
    }
    Ok(index)
}

/// Owns the engine session and every open document; the only thread that touches them.
fn worker_main(rx: &mut tokio::sync::mpsc::UnboundedReceiver<Cmd>) {
    let mut session = Session::new();
    let mut docs: HashMap<u32, OpenDoc> = HashMap::new();
    let mut next_handle: u32 = 1;
    while let Some(cmd) = rx.blocking_recv() {
        match cmd {
            Cmd::Open(req, reply) => {
                let _ = reply.send(open_doc(&mut session, &mut docs, &mut next_handle, req));
            }
            Cmd::PageCount(handle, reply) => {
                let _ = reply.send(match docs.get(&handle) {
                    Some(doc) => Ok(doc.page_count as u32),
                    None => Err("unknown document".to_owned()),
                });
            }
            Cmd::PageSize(handle, page, reply) => {
                let _ = reply.send(page_size(&docs, handle, page));
            }
            Cmd::Render(handle, page, dpi, reply) => {
                let _ = reply.send(render_page(&mut docs, handle, page, dpi));
            }
            Cmd::Save(handle, reply) => {
                let out = match docs.get(&handle) {
                    Some(doc) => session.save_bytes(doc.doc_id).map(|b| b.to_vec()).map_err(|e| e.to_string()),
                    None => Err("unknown document".to_owned()),
                };
                let _ = reply.send(out);
            }
            Cmd::Close(handle, reply) => {
                let out = match docs.remove(&handle) {
                    Some(_) => Ok(()),
                    None => Err("unknown document".to_owned()),
                };
                let _ = reply.send(out);
            }
        }
    }
}

fn open_doc(
    session: &mut Session,
    docs: &mut HashMap<u32, OpenDoc>,
    next_handle: &mut u32,
    req: OpenReq,
) -> Result<u32, String> {
    let bytes = Arc::new(req.bytes);
    let doc_id = session
        .open(req.name, None, bytes, req.password.as_deref())
        .map_err(|e| e.to_string())?;
    let doc = session
        .docs()
        .iter()
        .find(|d| d.id == doc_id)
        .ok_or_else(|| "opened document is not in the session".to_owned())?;
    let source = doc.export_source();
    let handle = *next_handle;
    *next_handle = next_handle.saturating_add(1);
    docs.insert(
        handle,
        OpenDoc {
            doc_id,
            page_count: source.pages,
            sizes: source.sizes,
            renderer: PageRenderer::new(source.bytes, source.config),
        },
    );
    Ok(handle)
}

fn page_size(docs: &HashMap<u32, OpenDoc>, handle: u32, page_1based: u32) -> Result<PageSize, String> {
    let doc = docs.get(&handle).ok_or_else(|| "unknown document".to_owned())?;
    let (width, height) = doc
        .sizes
        .get(index(page_1based, doc.page_count)?)
        .ok_or_else(|| "page out of range".to_owned())?;
    Ok(PageSize { width: *width, height: *height })
}

fn render_page(docs: &mut HashMap<u32, OpenDoc>, handle: u32, page_1based: u32, dpi: u32) -> Result<Vec<u8>, String> {
    let doc = docs.get_mut(&handle).ok_or_else(|| "unknown document".to_owned())?;
    let request = RenderRequest {
        page: index(page_1based, doc.page_count)?,
        kind: RequestKind::Pixels,
        tile: None,
        scale: dpi as f32 / 72.0,
        tag: 0,
    };
    let out = doc.renderer.render(request);
    if let Some(e) = out.error {
        return Err(e);
    }
    pdfcraft_engine::export::encode_image(out.width, out.height, &out.rgba, pdfcraft_engine::export::ImageFormat::Png)
}
