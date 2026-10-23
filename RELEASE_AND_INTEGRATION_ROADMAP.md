# Overline: Release Checklist & Integration Roadmap

This document summarizes the remaining steps before public release, outlines the multi-channel ChatGPT/AI integration plan, and details the zero-cloud-bill validation strategy.

---

## 1. Remaining Steps Before Release

### A. Agentic & Code Steps (Executable by Agent)
1. **Deploy Cloud Backend (`overline-backend`)**:
   - Containerize and deploy the FastAPI service to Google Cloud Run (or your preferred server).
   - Inject live environment secrets (`GEMINI_API_KEY`, Redis host, Firebase/Supabase Auth credentials).
2. **Connect Production Endpoints in Client**:
   - Point `BillingService` and `CloudAgentProvider` to the live backend URL (`https://api.overline.app`).
3. **Compile Release Artifacts**:
   - Run `tools/build-bundle.sh` to generate the production `Overline-release.aab`, ProGuard/R8 `mapping.txt`, and NDK `native-debug-symbols.zip`.
4. **Git Repository Push**:
   - Push the public `overline` repo (Apache 2.0 open-core) and private repos (`overline-app` and `overline-backend`).

### B. External Cloud & Service Setup (Technical Credentials)
1. **Google Cloud Service Account (Google Play Billing API)**:
   - Create GCP Service Account with `roles/androidpublisher`.
   - Mount key in `overline-backend` to verify purchase tokens via Developer API v3.
2. **Google Cloud Pub/Sub (Real-Time Developer Notifications - RTDN)**:
   - Create Pub/Sub topic and link it to Google Play Console for subscription renewals and cancellations.
3. **Production Telemetry / Crash Reporting**:
   - Set up Sentry (or Firebase Crashlytics) and bind the DSN in `TelemetryManager`.

### C. Manual Google Play Console Steps (Developer Account)
1. **Generate Production Upload Keystore**:
   - Run `keytool` locally to create `upload-keystore.jks` and fill in `android/key.properties` (never committed to Git).
2. **Create In-App Subscriptions**:
   - In Google Play Console under **Monetize > Products > Subscriptions**, create:
     - `overline_pro_monthly`
     - `overline_pro_annual`
   - Configure base plans, 7-day free trials, and grace periods.
3. **Store Listing Assets & Declarations**:
   - Upload 512×512 app icon, 1024×500 feature graphic, and minimum 4 phone screenshots.
   - Complete Data Safety declaration (declare purchase tokens & anonymous crash logs; declare zero permanent storage of user documents).
   - Provide public Privacy Policy URL.
4. **20-Tester / 14-Day Closed Testing Track**:
   - Mandatory for personal developer accounts created after Nov 13, 2023.
   - Invite 20+ testers via Google Groups and maintain closed testing for 14 continuous days.
5. **Production Access Survey & 5-Day Staged Rollout**:
   - Submit Google's 3-question survey.
   - Roll out to production in stages: `1% → 5% → 20% → 50% → 100%` while actively monitoring Android Vitals SLOs.

---

## 2. ChatGPT & AI Assistant Integration Plans

Overline uses its native Rust tool catalog (`PdfEngineApi.operationCatalog()`) to power two complementary integration surfaces without duplicating tool logic:

```
                               ┌────────────────────────────────────────────────────────┐
                               │                 Overline Core Engine                   │
                               │  (28 Rust Tools: rotate, redact, compress, forms, etc.) │
                               └───────────────────────────┬────────────────────────────┘
                                                           │
                      ┌────────────────────────────────────┴────────────────────────────────────┐
                      ▼                                                                         ▼
   【Path 1: Modern Plugin & MCP Bundle】                                    【Path 2: Custom GPT Action】
   - Surface: ChatGPT Desktop / AI Workspace / Claude                          - Surface: ChatGPT Web & Mobile App
   - Tech: MCP Server + SKILL.md + plugin.json                                 - Tech: FastAPI OpenAPI (/openapi.json)
   - Privacy: 100% Local on user's device ($0 server bill)                     - Privacy: Cloud gateway (overline-backend)
```

### Path 1: Modern Plugin (MCP Server + Skill)
- **Target**: Power users, developers, and desktop AI agents (Claude Desktop, Cursor, ChatGPT Desktop).
- **Architecture**:
  - `plugin.json`: Metadata, name (`overline`), description, icon.
  - `mcp_config.json`: Registers the local MCP server exposing Overline's 28 Rust tools.
  - `skills/pdf-editor/SKILL.md`: Teaches the agent the exact rules for inspecting and editing PDFs.
- **Benefits**: Runs locally on the user's computer, 100% offline, zero server compute cost, total privacy.

### Path 2: Custom GPT with OpenAPI Actions
- **Target**: Everyday consumers on ChatGPT Web and iOS/Android mobile apps.
- **Architecture**:
  - `overline-backend` automatically serves the OpenAPI 3.1 specification at `/openapi.json`.
  - Imported into OpenAI GPT Builder with one click.
  - User uploads a PDF in chat $\to$ ChatGPT calls `/v1/tools/execute` $\to$ backend processes with Rust core $\to$ returns modified PDF download link.
- **Benefits**: High-traffic customer acquisition channel on the OpenAI GPT Store; funnels free users to the Overline mobile app and Pro subscription.

---

## 3. Lean Validation Strategy: Launch Free Before Incurring Cloud Bills

> [!TIP]
> **Recommended Strategy**: Validate product-market fit using the 100% free offline app first before provisioning paid cloud infrastructure.

### Why Validate First?
1. **$0.00 Running Cost**:
   - All 28 manual PDF editing tools and the on-device Edge SLM run completely offline on the phone.
   - You incur **zero server bills, zero database costs, and zero API token burn**.
2. **Satisfies Google Play Requirements**:
   - You can conduct the entire 20-tester, 14-day closed testing track using only the offline features.
   - You verify crash-free rates, 16KB page alignment on Android 15, and pinch-zoom performance without spending money.
3. **Validate Real Demand for Cloud Pro**:
   - The UI includes the `PaywallSheet` ("Unlock Overline Pro").
   - You can measure click-through rates and collect email signups for Pro cloud features before provisioning cloud servers.
4. **De-Risked Cloud Rollout**:
   - Spin up the paid cloud backend (`overline-backend`, Redis, and Gemini API keys) only after confirming user engagement and initial subscription revenue.

