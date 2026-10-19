# Phase 6: Repository Separation & CI/CD Pipelines

**Target:** Split the codebase into the Two-Repository Open-Core architecture and configure automated GitHub Actions CI/CD for both testing and store deployments.  
**Prerequisites:** Phase 1 through Phase 5 complete.

---

## 1. Objectives & Deliverables
1. Establish the public repository `overline` containing the open-core Flutter UI, Rust bridge, and Edge SLM runtime (licensed under Apache 2.0).
2. Establish the private repository `overline-app` containing the commercial wrapper (In-App Purchases, `CloudAgentProvider`, paywalls, official app store branding, and production signing keys).
3. Configure GitHub Actions CI for the public repository: automated Rust tests, `cargo ndk` compilation, and Flutter test suite execution.
4. Configure GitHub Actions CI/CD for the private repository: automated Google Play App Bundle (`.aab`) builds and Fastlane delivery to Google Play Console.

---

## 2. Step-by-Step Implementation Instructions

### Step 6.1: Public Repository Setup (`overline`)
The public repository contains:
- `third_party/pdfcraft` (Pinned Git submodule)
- `rust/` (Native FFI adapter)
- `lib/`:
  - `widgets/` (All manual PDF editing sheets, canvas, viewers)
  - `services/` (Engine, diagnostics, recent documents, theme, page cache)
  - `services/agent/` (`AgentProvider` contract, `SlmModelStore`, `LocalSlmProvider`)
  - `main.dart`
- `test/` & `integration_test/`
- `tools/` (`build-apk.sh`, `env.sh`)
- `LICENSE` (Apache License 2.0)
- `NOTICE` (Upstream PdfCraft, Hayro, and font attributions)

*Execution Command:*
Ensure no proprietary credentials, backend URLs, or commercial billing keys exist in this branch before pushing publicly.

### Step 6.2: Private Commercial Repository Setup (`overline-app`)
1. Create new private repository `overline-app`.
2. Add the public core as a Git submodule or local path dependency:
   ```bash
   git submodule add https://github.com/sujayganorkar/overline.git core
   ```
3. Structure the private wrapper:
   ```
   overline-app/
   ├── core/                    # Submodule pointing to public overline
   ├── android/
   │   ├── key.properties       # Keystore secrets (gitignored)
   │   └── upload-keystore.jks  # Production signing key (gitignored)
   ├── lib/
   │   ├── main.dart            # Injects CloudAgentProvider + Billing
   │   └── pro/
   │       ├── billing/         # Google Play Billing service
   │       ├── agent/           # CloudAgentProvider (SSE client)
   │       ├── auth/            # Firebase / Supabase client
   │       └── ui/              # Paywall sheets & upgrade promos
   ├── fastlane/                # Fastlane metadata & supply credentials
   └── .github/workflows/       # Production CD workflows
   ```

### Step 6.3: Public Repository CI Workflow (`.github/workflows/ci.yml`)
In `overline/.github/workflows/ci.yml`:
```yaml
name: Continuous Integration

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive

      - name: Setup Rust Toolchain
        uses: dtolnay/rust-toolchain@stable
        with:
          toolchain: 1.99.0
          targets: aarch64-linux-android, x86_64-linux-android

      - name: Setup Flutter
        uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.47.7'
          channel: 'stable'

      - name: Run Rust Bridge Smoke Tests
        run: cargo test -p pdfcraft-mobile-api

      - name: Run Flutter Widget Tests
        run: |
          flutter pub get
          flutter test
```

### Step 6.4: Private Repository Release CD Workflow (`.github/workflows/release.yml`)
In `overline-app/.github/workflows/release.yml`:
```yaml
name: Production Release Build & Deploy

on:
  push:
    tags:
      - 'v*'

jobs:
  bundle:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive

      - name: Setup Toolchains
        uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.47.7'

      - name: Decode Production Keystore
        env:
          KEYSTORE_BASE64: ${{ secrets.ANDROID_UPLOAD_KEYSTORE_BASE64 }}
          KEY_PROPERTIES: ${{ secrets.ANDROID_KEY_PROPERTIES }}
        run: |
          echo "$KEYSTORE_BASE64" | base64 --decode > android/upload-keystore.jks
          echo "$KEY_PROPERTIES" > android/key.properties

      - name: Build Production AAB Bundle
        run: |
          chmod +x core/tools/build-bundle.sh
          core/tools/build-bundle.sh

      - name: Upload Artifacts
        uses: actions/upload-artifact@v4
        with:
          name: overline-release-bundle
          path: |
            dist/bundle/Overline-release.aab
            dist/bundle/mapping.txt
            dist/bundle/native-debug-symbols.zip
```

---

## 3. Verification & Acceptance Criteria
1. **Isolation**: The public `overline` repository builds and runs completely standalone as an offline PDF editor with the Edge SLM, without any references to private backend URLs or Google Play Billing packages.
2. **Submodule Integration**: `overline-app` successfully checks out `core/`, overlays the proprietary billing and cloud agent layers, and compiles without path conflicts.
3. **CI/CD Passing**: Pushes to `main` in the public repo trigger automated Rust and Flutter test passes in GitHub Actions.

