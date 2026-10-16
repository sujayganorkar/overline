# Privacy Policy for PdfCraft Mobile

**Effective Date:** October 16, 2026  
**Last Updated:** October 16, 2026

PdfCraft Mobile ("the Application") is built with an offline-first architecture prioritizing user privacy and data sovereignty. This Privacy Policy details how the Application handles your information.

---

### 1. Zero Cloud Uploads & Local Data Processing
- **100% On-Device Processing**: All PDF rendering, reading, parsing, text extraction, page manipulation, markup, and file generation are executed strictly on your local device using an embedded Rust core engine.
- **No Remote Servers**: The Application does not transmit your PDF documents, file names, metadata, comments, or extracted contents to any external cloud service, server, or API.

### 2. Digital Signatures & Security
- Any digital signatures you draw or import into the Application are stored exclusively in your device's protected internal app storage directory (`files/signatures/`).
- Signatures at rest are protected with file obfuscation to guard against opportunistic scanning on shared local file systems.
- You can delete any saved signature directly inside the app at any time, which permanently removes the file from disk using atomic unlinking.

### 3. Analytics & Diagnostics
- **No Third-Party Advertising ID Tracking**: The Application does not use advertising identifiers (AAID/GAID), marketing SDKs, or invasive device fingerprinting.
- **In-Memory Diagnostic Breadcrumbs**: The Application maintains a temporary, circular in-memory buffer (maximum 150 events) recording operational lifecycle states (e.g., file opened, memory pressure warnings, tool execution status).
- **Diagnostics Are Never Sent Automatically**: Diagnostic breadcrumbs remain exclusively in ephemeral RAM during your app session. They are erased when the process exits. You may choose to manually inspect or export these breadcrumbs via the built-in Diagnostics Sheet if you wish to report an issue to developers.

### 4. Storage & File Access Permissions
- The Application accesses only files that you explicitly select via the system document picker (`ACTION_OPEN_DOCUMENT` / `Storage Access Framework`) or share into the application via Android's share sheet (`ACTION_VIEW` / `ACTION_SEND`).
- Incoming temporary shared files are held in sandboxed cache storage and automatically pruned within 24 hours to conserve storage.
- The Application does not require or request broad `MANAGE_EXTERNAL_STORAGE` permissions.

### 5. Remote Feature Flags
- The Application may periodically query a lightweight configuration endpoint to retrieve emergency kill-switches or version advisories. This network call transmits no personal identification information (PII) or document data.

### 6. Children's Privacy
- The Application does not knowingly collect or solicit personal information from children under the age of 13.

### 7. Changes to This Policy
- Any updates to this policy will be reflected in the application's source repository and release notes.

### 8. Contact
- For privacy inquiries or questions, open an issue on the PdfCraft Mobile repository or contact the maintainers.

