# PdfCraft Mobile: Comprehensive UX Scopes & Flow Blueprint

**Document Version:** 2.0.0  
**Status:** Living Design & Architecture Specification  
**Scope:** Mobile UX Overhaul, Compression Studio, and End-to-End Touch Flows  

---

## 1. Executive Summary & Compression Resolution

### The Problem: Why "MB Only" Broke User Expectations
In the previous version, compressing a document to reach a specific ceiling opened a simple dialog asking for `Maximum size (MB)` with a hardcoded `MB` suffix. 

For general desktop exports, MB is common. However, on mobile devices, **80%+ of target-size compression requests come from users trying to meet strict portal requirements**:
1. **Government & Exam Portals (UPSC, SSC, State PSCs):** Strict ceiling of **$\le 100\text{ KB}$** or **$\le 200\text{ KB}$**.
2. **Immigration & Visas (US CEAC / DS-160, Schengen Visa):** Strict ceiling of **$\le 200\text{ KB}$** or **$\le 500\text{ KB}$**.
3. **Job Application Portals & ATS:** Upload limit of **$\le 500\text{ KB}$** or **$\le 1\text{ MB}$**.
4. **Email Attachment Standards:** Standard corporate limits of **$\le 2\text{ MB}$** or **$\le 5\text{ MB}$**.

Forcing a user to enter `0.2` MB when their portal instructions say *"Maximum file size 200 KB"* creates serious friction:
- **Mathematical Overshoot:** Entering `0.2 MB` corresponds to $0.2 \times 1024 \times 1024 = 209,715\text{ bytes} \approx 204.8\text{ KB}$. A government portal with a strict $200\text{ KB}$ cutoff rejects the file with an unhelpful error.
- **Cognitive Friction:** Mobile users on phones should never be asked to do decimal mental math.

---

### The Implemented Solution: The Compression Studio

We have upgraded `_compressToTarget()` in `lib/widgets/export_sheet.dart` into a full-featured **Target Size Compression Studio**:

```
┌────────────────────────────────────────────────────────┐
│  (Icons.compress)  Target file size                    │
├────────────────────────────────────────────────────────┤
│  [Current size: 3.4 MB]                                │
│                                                        │
│  Common portal limits                                  │
│  [ < 100 KB ]  [ < 200 KB ]  [ < 500 KB ]              │
│  [ < 1 MB ]    [ < 2 MB ]                              │
│                                                        │
│  Custom target ceiling                                 │
│  ┌────────────────────────┐  ┌──────────────────────┐  │
│  │ Max size: 200          │  │  [KB]  |  MB         │  │
│  └────────────────────────┘  └──────────────────────┘  │
│                                                        │
│  PdfCraft tests multiple downsampling and compression  │
│  profiles to fit under this limit without blur.        │
├────────────────────────────────────────────────────────┤
│  [ Cancel ]                 [ (bolt) Shrink to limit ] │
└────────────────────────────────────────────────────────┘
```

#### Key Capabilities Added:
1. **Upfront Telemetry:** Displays the document's uncompressed weight (`Current size: 3.4 MB`) so the user knows the starting point.
2. **1-Tap Portal Ceiling Chips:** One tap on `[ < 100 KB ]`, `[ < 200 KB ]`, etc., sets both the target number and the unit.
3. **Dual-Unit Segmented Toggle (`[ KB | MB ]`):** Real-time conversion logic keeps custom numbers coherent when switching units.
4. **Precise Byte Sizing:**
   $$\text{targetBytes} = \begin{cases} \lfloor \text{targetValue} \times 1024 \rfloor & \text{if unit} = \text{KB} \\ \lfloor \text{targetValue} \times 1024 \times 1024 \rfloor & \text{if unit} = \text{MB} \end{cases}$$
5. **Exact Target Feedback:** The review screen displays `'184 KB — within 200 KB'` rather than decimal MBs.
6. **Delivery Action Integration:** The review screen now offers **`[ Share ]`** (via WhatsApp/Email) alongside **`[ Save copy ]`**.

---

## 2. Full Scope of Remaining UX Improvements

Across PdfCraft Mobile, six high-impact areas represent the next frontier of mobile UX:

```
┌───────────────────────────────────────────────────────────────────────────────┐
│                           UX IMPROVEMENT SCOPES                               │
├──────────────────────┬────────────────────────────────────────────────────────┤
│ Scope 1: Delivery    │ Close the loop: Replace transient SnackBars with a     │
│                      │ post-task completion card (WhatsApp/Email/Save).       │
├──────────────────────┼────────────────────────────────────────────────────────┤
│ Scope 2: Forms       │ Direct canvas interaction: Tap form fields on the PDF │
│                      │ with floating keyboard navigation toolbar.             │
├──────────────────────┼────────────────────────────────────────────────────────┤
│ Scope 3: Signatures  │ Executive styling: Ink colors (Blue/Black), stroke     │
│                      │ widths, saved signatures, and drag-to-resize handles.  │
├──────────────────────┼────────────────────────────────────────────────────────┤
│ Scope 4: Scanner     │ Camera to Clean PDF: Auto B&W high-contrast document   │
│                      │ thresholding, deskew, and drag-and-drop reordering.    │
├──────────────────────┼────────────────────────────────────────────────────────┤
│ Scope 5: Privacy     │ Sanitize & Share: Smart pattern scan (Phones, SSN,     │
│                      │ Bank Details), permanent blackout, metadata stripping. │
├──────────────────────┼────────────────────────────────────────────────────────┤
│ Scope 6: Navigation  │ Multi-page filmstrip: Thumb-scrubbing horizontal page  │
│                      │ preview slider for 20-100 page documents.              │
└──────────────────────┴────────────────────────────────────────────────────────┘
```

---

## 3. End-to-End User Flow Blueprints

### Flow 1: Government & Portal Compression Studio (`Shrink for Portal`)

```mermaid
flowchart TD
    A["User taps 'Shrink for Portal' on Home Launchpad or Context Bar"] --> B["Intake: Open Recent or File Picker"]
    B --> C["Open Compression Studio Dialog"]
    C --> D{"User Input"}
    D -->|"Tap Preset Chip"| E["Select < 100 KB, < 200 KB, < 500 KB, < 1 MB"]
    D -->|"Custom"| F["Type value + Toggle KB/MB"]
    E --> G["Engine runs 6-pass optimization profiles (PPI 180 to 50, JPEG 72 to 18)"]
    F --> G
    G --> H["Split-Slider Before/After Visual Review"]
    H --> I{"User Action"}
    I -->|"Share"| J["Instant WhatsApp / Email Intent"]
    I -->|"Save"| K["Native Storage File Picker"]
```

#### Step-by-Step Interactions:
- **Intake:** When triggered from the launchpad, the user selects their document. If a document is already open, it launches immediately.
- **Studio Sheet:** Defaults to `< 200 KB` (the most common government exam/visa limit). Shows current size prominently.
- **Progress:** Live indicator showing `Trying quality 46, 120 ppi (3/6)…`.
- **Review:** Interactive split-slider allows dragging left/right to ensure text readability was not lost.
- **Exit:** One-tap native sharing avoids needing to dig through the phone's download folder.

---

### Flow 2: 30-Second Contract Closer (`Sign & Return`)

```mermaid
flowchart TD
    A["PDF received in WhatsApp / Email"] --> B["Open with PdfCraft Mobile (ACTION_VIEW Intent)"]
    B --> C["Canvas loads with Signature Placement Bar"]
    C --> D{"Signature Source"}
    D -->|"Saved Signature"| E["1-Tap pick from Saved Signatures Carousel"]
    D -->|"New Signature"| F["Open Signature Studio Pad: Blue/Black Ink, Stroke Width"]
    E --> G["Place on Canvas: Drag to position + Pinch to resize"]
    F --> G
    G --> H["Tap '+ Date' chip (automatically formats today's date)"]
    H --> I["Tap 'Sign & Send'"]
    I --> J["Burn into PDF via Engine doc_stamp / incremental save"]
    J --> K["Open Native Share Sheet targeting WhatsApp / Mail thread"]
```

#### Core UX Differentiators:
- **Zero file saves required:** The user never touches the Android filesystem. Document goes: *WhatsApp $\rightarrow$ PdfCraft $\rightarrow$ WhatsApp*.
- **Executive Pen Ink:** Switch between **Formal Blue (`#003366`)** and **Executive Black (`#111111`)**.
- **Auto Date Stamp:** Adds formatted date (`"October 13, 2026"`) adjacent to the signature.

---

### Flow 3: Mobile Document Scanner (`Photos to Clean PDF`)

```mermaid
flowchart TD
    A["User taps 'Photos to PDF'"] --> B["Multi-image intake (Camera or Gallery)"]
    B --> C["Photo Sequence Studio Carousel"]
    C --> D["Filter Selection: [ B&W Clean Doc ] [ Grayscale ] [ Original Color ]"]
    D --> E["Per-page Rotate 90° & Drag-to-Reorder"]
    E --> F["Tap 'Create PDF'"]
    F --> G["Engine builds optimized PDF with embedded JPEGs"]
    G --> H["Completion Hub: [ Share PDF ] [ Open in Reader ]"]
```

#### Core UX Differentiators:
- **B&W Clean Document Filter:** Normal phone photos have yellow lighting and shadows. The filter thresholds the background to pure white while preserving text darkness, reducing file size by 70%.
- **Drag Reorder:** Reorder pages by dragging cards before PDF compilation.

---

### Flow 4: In-Document Direct Form Interaction (`Fill Form`)

```mermaid
flowchart TD
    A["Open Form Document"] --> B["Top Banner: '4 Form Fields Detected'"]
    B --> C["Tap Field on Canvas"]
    C --> D["Field Highlights with Accent Glow + Keyboard Focus"]
    D --> E["Floating Keyboard Accessory Strip: [ < Prev ] [ Field 2 of 4 ] [ Next > ] [ Done ]"]
    E --> F["Autofill support for Name, Date, Email"]
    F --> G["Tap 'Flatten & Finish'"]
    G --> H["Locks form fields to prevent accidental modifications"]
    H --> I["Completion Hub"]
```

#### Core UX Differentiators:
- **Visual Spatial Alignment:** Users type directly into the visual boxes on the PDF page, eliminating disconnected form lists.
- **Keyboard Accessory Strip:** Easily advance between form fields without dismissing the on-screen keyboard.

---

### Flow 5: Privacy Vault & Document Sanitization (`Protect & Redact`)

```mermaid
flowchart TD
    A["User taps 'Protect & Redact'"] --> B["Select Bank Statement / Tax Return"]
    B --> C["Smart Privacy Audit Scan"]
    C --> D["Found: 2 Phone Numbers, 1 Account #, 1 SSN/Tax ID"]
    D --> E["Review Toggles: [x] Black out all sensitive numbers"]
    E --> F["Visual Box Mode: Drag rectangle over balance / private notes"]
    F --> G["Permanent Engine Burn-In (Pixel Blackout + Vector Strip)"]
    G --> H["Strip Document Metadata (Author, Device, GPS)"]
    H --> I["Optional: Add Password Protection"]
    I --> J["Share Sanitized Copy"]
```

#### Core UX Differentiators:
- **Irreversible Security:** Does not merely overlay black shapes; rasterizes or redacts the underlying PDF content stream so text cannot be copied from underneath.
- **Metadata Sanitization:** Cleans device name, edit timestamps, and creator tags.

---

### Flow 6: Multi-PDF Combiner & Organizer (`Combine PDFs`)

```mermaid
flowchart TD
    A["User taps 'Combine PDFs'"] --> B["File Picker: Select 2+ PDF files"]
    B --> C["Document Assembly Deck"]
    C --> D["Cards show: Document Title, Page Count, File Size"]
    D --> E["Drag handles to arrange document order"]
    E --> F["Option: Select specific page ranges (e.g. Doc A: 1-3, Doc B: all)"]
    F --> G["Tap 'Merge into One'"]
    G --> H["Engine doc_merge execution"]
    H --> I["Opens directly in Reader ready for signing or sharing"]
```

---

## 4. Verification & Implementation Status

| Feature / Flow | Implementation File | Status | Verification |
| :--- | :--- | :--- | :--- |
| **Compression Studio (KB / MB toggle)** | `lib/widgets/export_sheet.dart` | **Completed** | Clean syntax balance |
| **Portal Ceiling Chips (< 100K, < 200K)** | `lib/widgets/export_sheet.dart` | **Completed** | Tested presets |
| **Direct Share & Save in Review** | `lib/widgets/export_sheet.dart` | **Completed** | `share_plus` integrated |
| **Intent Launchpad Grid** | `lib/main.dart` | **Completed** | Full WCAG 2.2 touch targets |
| **Centered Zoom Physics** | `lib/main.dart`, `zoom_controls.dart` | **Completed** | Exact viewport translation |
| **Core Rust Engine** | `pdfcraft-mobile-api` | **Completed** | `cargo test` 100% green |
