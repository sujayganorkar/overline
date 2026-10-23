# Overline

<p align="center">
  <strong>Fast, private, offline PDF editor & signer powered by a native Rust engine.</strong>
</p>

<p align="center">
  <a href="https://github.com/sujayganorkar/overline/releases/latest">
    <img src="https://img.shields.io/github/v/release/sujayganorkar/pdfcraft-mobile?label=Release&color=blue" alt="Latest Release">
  </a>
  <img src="https://img.shields.io/badge/Platform-Android%2064--bit-green" alt="Platform">
  <img src="https://img.shields.io/badge/License-Apache%202.0%20%2F%20MIT-orange" alt="License">
  <a href="https://github.com/ImranR98/Obtainium">
    <img src="https://img.shields.io/badge/Obtainium-Compatible-purple" alt="Obtainium Compatible">
  </a>
</p>

---

Unlike web converters and bloated subscription PDF readers that upload your sensitive documents to remote cloud servers, **Overline** processes every single PDF operation directly on your device CPU. Your tax returns, legal contracts, and medical records never leave your phone.

---

## ✨ Features

- **⚡ Blazing Fast Native Core:** Powered by a high-performance native Rust engine with 64-bit SIMD acceleration and full Android 15 16 KB page-size support.
- **🔒 100% Offline & Private:** Zero account required, zero tracking, zero telemetry. Runs completely in airplane mode.
- **✍️ Digital Signatures:** Create handwritten or typed signatures once; place and resize anywhere. Signatures are encrypted locally in app-private flash storage.
- **📄 Core PDF Editing Suite:**
  - **Reorganize Pages:** Rotate, reorder, delete, duplicate, and insert blank pages with a responsive visual grid.
  - **In-Canvas Markup:** Highlighting, strikethroughs, pencil drawings, shapes, and text notes.
  - **Form Filling:** Fill out standard PDF form fields directly on your phone.
  - **Document Redaction:** Black out sensitive text and metadata before sharing.
  - **Merge & Split:** Combine multiple documents or extract specific page ranges.
- **🌙 Comfortable Reading:** Dark theme support with optional PDF color inversion for comfortable nighttime reading.
- **🛡️ Auto Draft Recovery:** Crash-resilient architecture that automatically preserves your unsaved edits if Android terminates the app in the background.
- **🔄 Built-In Update Checker:** In-app notification when new GitHub releases are available, plus direct compatibility with Obtainium for background updates.

---

## 📲 Download & Installation

### Option 1: Direct APK Download
Download the latest pre-compiled APK directly from the [GitHub Releases](https://github.com/sujayganorkar/overline/releases/latest) page:

1. Download **`Overline-latest.apk`**.
2. Tap the downloaded file and choose **Install** (allow *Install unknown apps* if prompted).
3. *(Optional)* Verify the SHA-256 checksum:
   ```bash
   sha256sum -c Overline-latest.apk.sha256
   ```

### Option 2: Automatic Updates via Obtainium (Recommended)
If you use [Obtainium](https://github.com/ImranR98/Obtainium):
1. Copy this repository URL: `https://github.com/sujayganorkar/overline`.
2. Open Obtainium, tap **Add App**, and paste the URL.
3. Obtainium will track releases and update Overline seamlessly in the background.

---

## 🏗️ Architecture

Overline uses a high-performance hybrid architecture:
- **UI & Presentation:** Flutter (Material 3) with custom gestures, multi-touch canvas viewport, and adaptive layout.
- **Bridge Layer:** [`flutter_rust_bridge`](https://github.com/fzyzcjy/flutter_rust_bridge) providing zero-copy asynchronous FFI between Dart and native code.
- **Engine Core:** Native Rust library cross-compiled for `arm64-v8a` and `x86_64` targets with 16 KB ELF page alignment for modern Linux/Android kernels.

---

## 🛠️ Building from Source

### Prerequisites
- **Flutter SDK:** 3.47+ (Dart 3.13+)
- **Rust Toolchain:** `nightly` or `stable` with Android targets (`aarch64-linux-android`, `x86_64-linux-android`)
- **Android NDK:** r27c+ (`cargo-ndk`)

### Quick Build Instructions

```bash
# 1. Clone the repository with submodules
git clone --recurse-submodules https://github.com/sujayganorkar/overline.git
cd overline

# 2. Source the environment paths
source tools/env.sh

# 3. Fetch dependencies
flutter pub get

# 4. Compile native Rust libraries and assemble release APK
tools/build-apk.sh
```

The resulting binary will be saved at `dist/apk/Overline-latest.apk`.

To run all unit and widget tests:
```bash
flutter test
```

---

## 📜 Legal & Open Source Attribution

Overline is dual-licensed under the **Apache License 2.0** and the **MIT License**.

- **Engine Core:** Powered by the open-source [PdfCraft](https://github.com/storytold/pdfcraft) engine (MIT / Apache-2.0, © ArtCraft Team and contributors).
- **Bundled Fonts & Assets:** Bundles Hayro (Apache-2.0 / MIT), Foxit Type 1 fonts (BSD-3-Clause), Adobe CMap (BSD-3-Clause), and SIL OFL typefaces.
- See [`docs/PRIVACY_POLICY.md`](docs/PRIVACY_POLICY.md) for privacy practices and [`docs/DATA_SAFETY.md`](docs/DATA_SAFETY.md) for Android permission details.
