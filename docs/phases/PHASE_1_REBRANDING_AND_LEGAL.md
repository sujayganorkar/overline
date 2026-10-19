# Phase 1: Rebranding & Legal Foundation

**Target:** Rename application to Overline, establish open-source compliance, and configure 16 KB memory page alignment.  
**Prerequisites:** Working clone with Rust and Flutter toolchains.

---

## 1. Objectives & Deliverables
1. Migrate Android Application ID to `app.overline.pdf`.
2. Move Kotlin `MainActivity.kt` and update namespace to `app.overline.pdf`.
3. Update iOS display name and bundle identifier in `Info.plist` and `project.pbxproj`.
4. Update `pubspec.yaml` package name to `overline` and update all 37 test imports.
5. Replace in-app user strings ("PdfCraft" -> "Overline").
6. Regenerate app launcher icons from Overline brand art.
7. Implement the in-app **Open Source Licenses & Attributions** screen.
8. Add 16 KB ELF memory page alignment flags to `.cargo/config.toml`.

---

## 2. Step-by-Step Implementation Instructions

### Step 1.1: Android Gradle & Kotlin Namespace
1. Edit `android/app/build.gradle.kts`:
   - Line 11: Change `namespace = "com.pdfcraft.pdfcraft_mobile"` to `namespace = "app.overline.pdf"`.
   - Line 22: Change `applicationId = "com.pdfcraft.pdfcraft_mobile"` to `applicationId = "app.overline.pdf"`.
2. Create directory:
   ```bash
   mkdir -p android/app/src/main/kotlin/app/overline/pdf
   ```
3. Move `MainActivity.kt`:
   ```bash
   git mv android/app/src/main/kotlin/com/pdfcraft/pdfcraft_mobile/MainActivity.kt \
          android/app/src/main/kotlin/app/overline/pdf/MainActivity.kt
   rmdir android/app/src/main/kotlin/com/pdfcraft/pdfcraft_mobile 2>/dev/null || true
   rmdir android/app/src/main/kotlin/com/pdfcraft 2>/dev/null || true
   ```
4. In `android/app/src/main/kotlin/app/overline/pdf/MainActivity.kt`:
   - Line 1: Change to `package app.overline.pdf`.
   - Line 28: Change `"pdfcraft-workspace"` to `"overline-workspace"`.
   - Line 122: Change `CHANNEL = "com.pdfcraft.pdfcraft_mobile/paths"` to `CHANNEL = "app.overline.pdf/paths"`.
5. In `android/app/src/main/AndroidManifest.xml`:
   - Line 3: Change `android:label="PdfCraft Mobile"` to `android:label="Overline"`.

### Step 1.2: iOS Configuration
1. In `ios/Runner/Info.plist`:
   - Line 10: Change `<string>Pdfcraft Mobile</string>` to `<string>Overline</string>`.
   - Line 18: Change `<string>pdfcraft_mobile</string>` to `<string>overline</string>`.
2. In `ios/Runner.xcodeproj/project.pbxproj`:
   - Replace all occurrences of `com.pdfcraft.pdfcraftMobile` with `app.overline.pdf`.

### Step 1.3: Flutter & Dart Renaming
1. In `pubspec.yaml`:
   - Line 1: Change `name: pdfcraft_mobile` to `name: overline`.
   - Line 2: Change description to `"Overline - Fast, private, offline PDF editor & signer powered by a native Rust engine."`.
2. In `lib/services/pdf_engine.dart`:
   - Line 134: Change `const channel = MethodChannel('com.pdfcraft.pdfcraft_mobile/paths');` to:
     `const channel = MethodChannel('app.overline.pdf/paths');`.
3. Mass-replace all package imports across tests and code:
   ```bash
   find test/ integration_test/ lib/ -type f -name "*.dart" -exec sed -i 's|package:pdfcraft_mobile/|package:overline/|g' {} +
   ```

### Step 1.4: In-App User Strings Replacement
Update user-facing copy in the following files:
1. `lib/main.dart`:
   - Line 135: Change `title: 'PdfCraft Mobile'` to `title: 'Overline'`.
   - Line 362: Change `'Engine ready (PdfCraft Rust core)'` to `'Engine ready (Overline Rust core)'`.
   - Line 1278: Change `'Shared from PdfCraft Mobile'` to `'Shared from Overline'`.
   - Line 1432: Change `'PdfCraft recovered an automatic copy of $originalName. Restore it now?'` to `'Overline recovered an automatic copy of $originalName. Restore it now?'`.
   - Line 3355: Change `_name ?? 'PdfCraft Mobile'` to `_name ?? 'Overline'`.
2. `lib/widgets/agent_command_sheet.dart`:
   - Line 41: Change `Text('Ask PdfCraft')` to `Text('Ask Overline')`.
   - Line 44: Change `'...PdfCraft will show the next step before making a change.'` to `'...Overline will show the next step before making a change.'`.
3. `lib/widgets/task_catalog.dart`:
   - Line 283: Change `'Ask PdfCraft'` to `'Ask Overline'`.
4. `lib/widgets/secure_sheet.dart`:
   - Line 491: Change `'...PdfCraft checks that marked text is no longer readable.'` to `'...Overline checks that marked text is no longer readable.'`.
5. `lib/widgets/recipes_sheet.dart`:
   - Line 279: Change `'PdfCraft will place reversible redaction marks...'` to `'Overline will place reversible redaction marks...'`.

### Step 1.5: Branding & Launcher Icon Generation
1. Place the Overline brand icon at `assets/icon/app_logo.png`.
2. Execute icon generation:
   ```bash
   tools/generate-icons.sh assets/icon/app_logo.png
   ```
3. Update `fastlane/metadata/android/en-US/`:
   - `title.txt`: `Overline: Fast PDF Editor`
   - `short_description.txt`: `Fast, private, offline PDF editor & signer powered by a native Rust engine.`
   - `full_description.txt`: Search and replace "PdfCraft" with "Overline".

### Step 1.6: Open-Source Legal Attribution
In `lib/main.dart` or `lib/widgets/reader_controls.dart`, add an "About Overline" option in the document actions or home options menu:
```dart
void showOverlineAboutDialog(BuildContext context) {
  showAboutDialog(
    context: context,
    applicationName: 'Overline',
    applicationVersion: '1.0.0',
    applicationIcon: Image.asset('assets/icon/app_logo.png', width: 48, height: 48),
    applicationLegalese: '© 2026 Overline Contributors.\n\n'
        'Engine powered by PdfCraft (MIT / Apache-2.0, © ArtCraft Team and contributors).\n'
        'Bundles Hayro (Apache-2.0 / MIT), Foxit Type 1 fonts (BSD-3-Clause), '
        'Adobe CMap (BSD-3-Clause), and SIL OFL typefaces.',
  );
}
```

### Step 1.7: 16 KB ELF Page-Size Alignment
Create `.cargo/config.toml` at the project root:
```toml
[target.aarch64-linux-android]
rustflags = ["-C", "link-arg=-Wl,-z,max-page-size=16384"]

[target.x86_64-linux-android]
rustflags = ["-C", "link-arg=-Wl,-z,max-page-size=16384"]
```

---

## 3. Verification & Acceptance Criteria
Run the following verification suite:
```bash
# 1. Verify Rust smoke tests pass with updated cargo configs
cargo test -p pdfcraft-mobile-api

# 2. Verify no stale imports remain
grep -rn "package:pdfcraft_mobile" lib/ test/ integration_test/ && exit 1 || echo "All imports updated"

# 3. Verify no unwanted 'PdfCraft' strings remain in user-facing UI
grep -rn "PdfCraft Mobile" lib/ && exit 1 || echo "User-facing strings clean"

# 4. Verify Flutter tests pass
source tools/env.sh
flutter test
```

