# Overline: Rebranding, Hardening & Store Release Master Guide

**Document Status:** Actionable Implementation & Operations Guide  
**Target Release:** Overline 1.0 (Android First)  
**Applicable Codebase:** `pdfcraft-mobile` -> `overline`

---

## 1. Executive Summary

This document details the exact, step-by-step procedures required to:
1. Rebrand this application from **PdfCraft Mobile** to **Overline**.
2. Fulfill open-source legal compliance and trademark disassociation from upstream `pdfcraft`.
3. Configure production signing, 16 KB ELF memory page alignment, and release bundle generation.
4. Establish production telemetry, crash observability, and remote kill switches.
5. Navigate Google Play Store requirements (including the mandatory 20-tester closed testing period).

---

## 2. Phase 1: Rebranding to "Overline" Checklist

### 2.1 Android Application Identity & Package Renaming
*Target files:*
- `android/app/build.gradle.kts`
- `android/app/src/main/kotlin/com/pdfcraft/pdfcraft_mobile/MainActivity.kt`
- `android/app/src/main/AndroidManifest.xml`

#### Steps:
1. **Choose Immutable Application ID**:
   - Set `applicationId = "app.overline.pdf"` (or your preferred registered domain).
   - *Note: Once uploaded to Google Play, the Application ID can never be altered.*
2. **Update Gradle Namespace**:
   ```kotlin
   // android/app/build.gradle.kts
   android {
       namespace = "app.overline.pdf"
       defaultConfig {
           applicationId = "app.overline.pdf"
           ...
       }
   }
   ```
3. **Move Kotlin Source Directory**:
   - Relocate `android/app/src/main/kotlin/com/pdfcraft/pdfcraft_mobile/MainActivity.kt` to:
     `android/app/src/main/kotlin/app/overline/pdf/MainActivity.kt`
   - Update the package statement:
     ```kotlin
     package app.overline.pdf
     ```
   - Update `CHANNEL` constant:
     ```kotlin
     companion object {
         private const val CHANNEL = "app.overline.pdf/paths"
     }
     ```
   - Update support workspace directory name:
     ```kotlin
     val dir = File(filesDir, "overline-workspace")
     ```
4. **Update Android App Label**:
   ```xml
   <!-- android/app/src/main/AndroidManifest.xml -->
   <application
       android:label="Overline"
       android:icon="@mipmap/ic_launcher"
       ... >
   ```

---

### 2.2 iOS Metadata Renaming
*Target files:*
- `ios/Runner/Info.plist`
- `ios/Runner.xcodeproj/project.pbxproj`

#### Steps:
1. **Update Info.plist**:
   ```xml
   <key>CFBundleDisplayName</key>
   <string>Overline</string>
   <key>CFBundleName</key>
   <string>overline</string>
   ```
2. **Update Bundle Identifier in Xcode Project**:
   - Replace `PRODUCT_BUNDLE_IDENTIFIER = com.pdfcraft.pdfcraftMobile;` with `app.overline.pdf`.

---

### 2.3 Flutter Package & Code Renames
*Target files:*
- `pubspec.yaml`
- `lib/services/pdf_engine.dart`
- `lib/main.dart`
- `test/**` and `integration_test/**` (37 files)

#### Steps:
1. **Update `pubspec.yaml`**:
   ```yaml
   name: overline
   description: "Overline - Fast, private, offline PDF editor & signer powered by a native Rust engine."
   ```
2. **Update MethodChannel in Dart**:
   ```dart
   // lib/services/pdf_engine.dart
   const channel = MethodChannel('app.overline.pdf/paths');
   ```
3. **Batch-Replace Package Imports Across Tests & Integration Tests**:
   - Replace `import 'package:pdfcraft_mobile/` with `import 'package:overline/`.
   - Command:
     ```bash
     find test/ integration_test/ lib/ -type f -name "*.dart" -exec sed -i 's|package:pdfcraft_mobile/|package:overline/|g' {} +
     ```
4. **Update In-App User-Facing Strings**:

| File | Current String | New String |
| :--- | :--- | :--- |
| `lib/main.dart:135` | `title: 'PdfCraft Mobile'` | `title: 'Overline'` |
| `lib/main.dart:362` | `'Engine ready (PdfCraft Rust core)'` | `'Engine ready (Overline Rust core)'` |
| `lib/main.dart:1278` | `'Shared from PdfCraft Mobile'` | `'Shared from Overline'` |
| `lib/main.dart:1432` | `'PdfCraft recovered an automatic copy...'` | `'Overline recovered an automatic copy...'` |
| `lib/widgets/agent_command_sheet.dart` | `'Ask PdfCraft'` | `'Ask Overline'` |
| `lib/widgets/recipes_sheet.dart` | `'PdfCraft will place reversible redaction marks...'` | `'Overline will place reversible redaction marks...'` |
| `lib/widgets/secure_sheet.dart` | `'...PdfCraft checks that marked text is no longer readable.'` | `'...Overline checks that marked text is no longer readable.'` |

---

### 2.4 Branding & App Icon Regeneration
1. Replace `assets/icon/app_logo.png` with the new Overline brand icon (high-resolution PNG, minimum 1024×1024).
2. Execute the icon generation script:
   ```bash
   chmod +x tools/generate-icons.sh
   tools/generate-icons.sh assets/icon/app_logo.png
   ```
3. Update `fastlane/metadata/android/en-US/`:
   - `title.txt`: `Overline: Fast PDF Editor`
   - `short_description.txt`: `Fast, private, offline PDF editor & signer powered by a native Rust engine.`
   - `full_description.txt`: Replace all mentions of "PdfCraft" with "Overline".

---

## 3. Phase 2: Legal & Open-Source Compliance

### 3.1 Upstream Attribution & Trademark Separation
Upstream `pdfcraft` is dual-licensed under **MIT / Apache-2.0**, but explicitly reserves all trademarks:
> *"The ArtCraft name, wordmark and logos in docs/brand/ are trademarks of the ArtCraft Team. They are not open source..."*

Renaming the app and using your own logo satisfies trademark compliance. However, **both MIT and Apache 2.0 require including the original copyright notice and license texts in any binary distribution**.

### 3.2 Add In-App Legal Licenses Screen
Currently, the app lacks an About / Licenses entrypoint. Add an "About Overline & Open Source Licenses" action to the main screen header or options menu:

```dart
// Example implementation in lib/main.dart or options sheet
void _showAboutAndLicenses(BuildContext context) {
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

### 3.3 Public Privacy Policy Hosting
Google Play strictly requires an **active, publicly accessible HTTPS URL** for the Privacy Policy.
1. Create a public repository page (e.g. `https://sujayganorkar.github.io/overline/privacy`).
2. Publish the contents of `docs/PRIVACY_POLICY.md` (updated with "Overline" name and contact information).
3. Paste the public URL into **Google Play Console > App Content > Privacy Policy**.

---

## 4. Phase 3: Production Signing & Android 15 Alignment

### 4.1 Production Keystore Setup
Google Play will reject an App Bundle signed with a debug key.

1. **Generate Release Upload Keystore**:
   ```bash
   keytool -genkey -v -keystore android/upload-keystore.jks \
     -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```
2. **Create `android/key.properties`** (Ensure this file is in `.gitignore`!):
   ```properties
   storePassword=<keystore-password>
   keyPassword=<key-password>
   keyAlias=upload
   storeFile=../upload-keystore.jks
   ```
3. **Enroll in Google Play App Signing**:
   - Google maintains the master signing key; you upload bundles signed with this upload key.

### 4.2 Android 15 & 16 KB Memory Page Alignment
Google Play guidelines for 2025/2026 require native shared libraries (`.so`) to support 16 KB ELF alignment for modern Linux kernels.

Create or update `.cargo/config.toml` at the project root:
```toml
[target.aarch64-linux-android]
rustflags = ["-C", "link-arg=-Wl,-z,max-page-size=16384"]

[target.x86_64-linux-android]
rustflags = ["-C", "link-arg=-Wl,-z,max-page-size=16384"]
```

### 4.3 App Bundle Build & Verification
Use the hardened production build script:
```bash
source tools/env.sh
tools/build-bundle.sh
```
This generates:
- `dist/bundle/Overline-release.aab`
- `dist/bundle/mapping.txt` (Upload to Play Console for ProGuard/R8 de-obfuscation)
- `dist/bundle/native-debug-symbols.zip` (Upload to Play Console for native Rust crash symbolication)

---

## 5. Phase 4: Production Observability & Remote Kill Switches

### 5.1 Real Crash Reporting Sink
`lib/services/telemetry_sink.dart` provides `TelemetrySink`. The app currently records errors only in ephemeral device RAM.
To capture crashes in the wild:
1. Integrate a privacy-focused crash provider (e.g., Sentry or Firebase Crashlytics).
2. Implement `TelemetrySink`:
   ```dart
   class ProductionCrashlyticsSink implements TelemetrySink {
     @override
     void recordEvent(String name, {Map<String, dynamic>? parameters}) {
       // Optional analytics if user opted in
     }

     @override
     void recordError(Object error, StackTrace? stack, {String? reason, bool fatal = false}) {
       // Forward to Sentry/Crashlytics
     }

     @override
     void setCustomKey(String key, Object value) {
       // Set diagnostic breadcrumbs
     }
   }
   ```
3. Register on app startup:
   ```dart
   TelemetryManager.instance.registerSink(ProductionCrashlyticsSink());
   ```

### 5.2 Dynamic Feature Flag Endpoint
`FeatureFlagService` in `lib/services/feature_flags.dart` already supports killing specific tools (e.g. `doc_ocr`, `doc_convert`) in case of native panics or CVEs.
Connect `initialize()` to fetch from a static JSON endpoint (e.g., hosted on GitHub Raw or a lightweight Cloudflare Worker):
```json
{
  "flags": {
    "tool:doc_ocr": true,
    "tool:doc_convert": true
  },
  "disabled_notices": {
    "tool:doc_ocr": "OCR is temporarily undergoing maintenance."
  }
}
```

---

## 6. Phase 5: Google Play Console Release Flow

### 6.1 Account Requirements
For Google Play developer accounts created after November 13, 2023:
- **Mandatory Closed Testing**: Must recruit at least **20 testers opted in for at least 14 continuous days** before requesting production access.
- **Verification**: Complete D-U-N-S verification (for organizations) or government ID verification (for individuals).

### 6.2 Staged Rollout Strategy
Follow `docs/STAGED_ROLLOUT_PLAYBOOK.md`:
1. **Internal Track**: Sanity test on internal devices.
2. **Closed Testing Track**: 20 testers for 14 days.
3. **Open Beta Track**: Opt-in testing for real-world crash validation.
4. **Production Staged Rollout**:
   - Day 1: 1%
   - Day 2: 5%
   - Day 3: 20%
   - Day 4: 50%
   - Day 5: 100%

Monitor **Android Vitals**:
- Keep Crash Rate < 0.2% (Limit: 1.09%).
- Keep ANR Rate < 0.1% (Limit: 0.47%).

