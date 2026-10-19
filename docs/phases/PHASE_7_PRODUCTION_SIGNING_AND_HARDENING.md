# Phase 7: Production Signing, Observability & Hardening

**Target:** Configure Google Play release upload signing, bind production crash telemetry, connect the live remote kill switch, and generate release bundles.  
**Prerequisites:** Phase 1 through Phase 6 complete.

---

## 1. Objectives & Deliverables
1. Generate the production release upload key using `keytool` and configure `android/key.properties`.
2. Implement a production crash reporting sink (`SentrySink` or `FirebaseCrashlyticsSink`) bound to `TelemetryManager`.
3. Connect `FeatureFlagService` to a live remote config endpoint to enable emergency tool shutdowns.
4. Execute `tools/build-bundle.sh` to produce the hardened Google Play App Bundle (`.aab`), ProGuard/R8 `mapping.txt`, and NDK `native-debug-symbols.zip`.

---

## 2. Step-by-Step Implementation Instructions

### Step 7.1: Production Keystore Generation
Google Play requires an upload key to verify developer authenticity:
```bash
# Execute inside the android/ directory of overline-app
keytool -genkey -v \
  -keystore upload-keystore.jks \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000 \
  -alias upload \
  -dname "CN=Overline Release, OU=Mobile, O=Overline, L=Unknown, ST=Unknown, C=IN"
```

Create `android/key.properties`:
```properties
storePassword=<YOUR_STORE_PASSWORD>
keyPassword=<YOUR_KEY_PASSWORD>
keyAlias=upload
storeFile=../upload-keystore.jks
```
*Security Invariant:* Add `android/key.properties` and `android/upload-keystore.jks` to `.gitignore`. Never commit them to Git. Keep offline encrypted backups.

### Step 7.2: Production Crash Telemetry Sink
`lib/services/telemetry_sink.dart` provides an abstract `TelemetrySink` interface. Bind it to **Sentry** (or Firebase Crashlytics):

1. Add Sentry to `pubspec.yaml`:
   ```yaml
   dependencies:
     sentry_flutter: ^8.14.0
   ```
2. Create `lib/services/sentry_telemetry_sink.dart`:
   ```dart
   import 'package:sentry_flutter/sentry_flutter.dart';
   import 'telemetry_sink.dart';

   class SentryTelemetrySink implements TelemetrySink {
     @override
     void recordEvent(String name, {Map<String, dynamic>? parameters}) {
       Sentry.addBreadcrumb(Breadcrumb(
         category: 'app_event',
         message: name,
         data: parameters,
         level: SentryLevel.info,
       ));
     }

     @override
     void recordError(Object error, StackTrace? stack, {String? reason, bool fatal = false}) {
       Sentry.captureException(
         error,
         stackTrace: stack,
         withScope: (scope) {
           if (reason != null) scope.setContexts('reason', {'message': reason});
           if (fatal) scope.level = SentryLevel.fatal;
         },
       );
     }

     @override
     void setCustomKey(String key, Object value) {
       Sentry.configureScope((scope) => scope.setTag(key, value.toString()));
     }
   }
   ```
3. Initialize in `main.dart`:
   ```dart
   void main() async {
     WidgetsFlutterBinding.ensureInitialized();
     TelemetryManager.instance.registerSink(SentryTelemetrySink());
     await SentryFlutter.init(
       (options) {
         options.dsn = 'https://<PUBLIC_KEY>@sentry.io/<PROJECT_ID>';
         options.tracesSampleRate = 0.1;
       },
       appRunner: () => runApp(const OverlineApp()),
     );
   }
   ```

### Step 7.3: Live Remote Kill Switch Connection
In `lib/services/feature_flags.dart`, update `initialize()` to fetch dynamic flags from a secure static JSON endpoint (e.g. GitHub Gist or Cloudflare Worker):
```dart
Future<void> fetchRemoteFlags() async {
  try {
    final response = await http.get(Uri.parse('https://config.overline.app/flags.json'))
        .timeout(const Duration(seconds: 4));
    if (response.statusCode == 200) {
      final config = jsonDecode(response.body) as Map<String, dynamic>;
      await applyConfig(config, persist: true);
    }
  } catch (e, st) {
    AppDiagnostics.instance.recordError(e, st, category: 'feature_flags_remote');
  }
}
```

### Step 7.4: Build Production App Bundle
Execute the automated release script:
```bash
source tools/env.sh
tools/build-bundle.sh
```

Inspect output directory `dist/bundle/`:
- `Overline-release.aab`: The binary upload for Google Play Console.
- `mapping.txt`: R8 obfuscation mapping (ensures obfuscated stack traces show exact Java/Kotlin file names and lines).
- `native-debug-symbols.zip`: NDK debug symbols for `libpdfcraft_mobile_api.so` (ensures native Rust panics de-obfuscate to file paths and line numbers in Google Play Android Vitals).
- `release-info.txt`: SHA-256 hash and build timestamp.

---

## 3. Verification & Acceptance Criteria
1. **Keystore Signing**: Inspect bundle signing with `jarsigner -verify -verbose -certs dist/bundle/Overline-release.aab` $\to$ must show `CN=Overline Release` (not Android Debug).
2. **Crash Capturing**: Triggering a test exception in debug mode successfully sends an event to the Sentry dashboard with breadcrumbs and device info.
3. **Artifact Integrity**: `native-debug-symbols.zip` contains symbols for both `arm64-v8a` and `x86_64` ABIs.

