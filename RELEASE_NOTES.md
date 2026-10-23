# Overline v1.0.0 - Fast, Private, Offline PDF Editor

Overline is a fast, offline, privacy-first PDF editor and signer for Android powered by a high-performance native Rust core. 

Unlike web converters and bloated subscription PDF readers, Overline executes document modifications directly on your device CPU—your tax returns, legal contracts, and medical records never leave your phone.

### ✨ Key Features
- **⚡ Blazing Fast Native Engine:** Built in Rust with 64-bit SIMD optimization and Android 15 16 KB page-size support.
- **🔒 100% Offline & Private:** Zero account required, zero cloud uploads. Operates completely in airplane mode.
- **✍️ Digital Signatures:** Draw or type signatures once; place and resize anywhere. Signatures are encrypted locally in app-private flash.
- **📄 Core PDF Tools:**
  - Fast page reorganizer: Rotate, reorder, delete, and extract pages.
  - Text markup: Highlighting, strikethroughs, and freehand annotations.
  - In-canvas text editing and document redaction.
  - Multi-file merge and split.
- **🛡️ Crash Resilience:** Automatic draft recovery preserves your edits even if Android closes the app in the background.
- **🔄 Auto-Update Notification:** Built-in lightweight notification check for new GitHub releases.
- **📲 Compatible with Obtainium:** Paste this repository link into Obtainium to receive instant background updates.

### 📦 Download & Verification
- **APK (ARM64 & x86_64):** Download `Overline-latest.apk` below.
- **Verify Checksum:**
  ```bash
  sha256sum -c Overline-latest.apk.sha256
  ```
