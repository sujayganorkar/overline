# Overline: Open-Core Strategy & Hybrid Agent Architecture

**Status:** Architecture Blueprint & Implementation Strategy  
**Product:** Overline (Flutter + Rust PDF Editor + Hybrid Agent)  
**Target Delivery:** Open Core (FOSS) + Commercial Cloud Agent (Subscription)

---

## 1. Vision & Strategy

Overline is built on an **Open-Core** model:
1. **The Core (Open Source)**: A privacy-first, 100% offline mobile PDF editor covering all tools ported from the `pdfcraft` Rust engine, featuring touch-first Flutter UX, plus an **embedded on-device Small Language Model (SLM)** runtime.
2. **The Cloud Extension (Proprietary & Subscription)**: A managed, zero-configuration cloud agent inference layer powered by leading foundation models (e.g. Gemini, Claude) with no user-supplied keys (**No BYOK**), monetized through in-app subscriptions.

---

## 2. Open-Core Boundary Matrix

The boundary between open-source and proprietary code is both a legal decision and a **financial security boundary**. Exposing cloud endpoints, authentication schemes, or entitlement checks in open source invites piracy and server resource abuse.

| Component | Code Visibility | Repository | Description |
| :--- | :--- | :--- | :--- |
| **Rust PDF Engine & Bridge** | **Open Source** (Apache 2.0) | `overline` (Public) | Upstream engine wrapper, FFI bridge (`rust/`, `lib/bridge/`), thread pool. |
| **Manual Touch PDF UI & Workspace** | **Open Source** (Apache 2.0) | `overline` (Public) | Canvas, annotation layers, page grid, form editor, crop, reader controls. |
| **Typed Tool Catalog / Schemas** | **Open Source** (Apache 2.0) | `overline` (Public) | Schema-driven PDF automation tools (`TaskCatalog`, schema validation). |
| **Edge SLM Runtime & Inference** | **Open Source** (Apache 2.0) | `overline` (Public) | On-device SLM execution via `llama.cpp` / `mediapipe` bindings, GGUF/ONNX loaders. |
| **Local Agent System Prompts** | **Open Source** (Apache 2.0) | `overline` (Public) | Prompts and few-shot examples tuned for small on-device models. |
| **Cloud Inference Gateway Backend** | **Proprietary** (Private) | `overline-backend` (Private) | Server-side proxy: user auth, subscription verification, token accounting, LLM calls. |
| **In-App Billing & Subscriptions** | **Proprietary** (Private) | `overline-app` (Private) | Google Play Billing / RevenueCat integration, paywall UI, entitlement sync. |
| **Cloud Agent Client Adapter** | **Proprietary** (Private) | `overline-app` (Private) | Authenticated network streaming client (SSE / WebSocket), encrypted document payload transport. |
| **Official Store Branding & Keystores** | **Proprietary** (Private) | `overline-app` (Private) | Official Overline app store assets, upload keystores, fastlane credentials. |

---

## 3. The Unified Agent Architecture

Both the **Edge SLM** and the **Cloud Agent** must manipulate documents identically without divergent codebases. This is achieved by anchoring both agents to the **typed tool catalog** via an abstract `AgentProvider` interface.

```
                           ┌───────────────────────────────────────────────┐
                           │            lib/widgets/task_catalog           │
                           │   Typed Tools: rotate, redact, ocr, fill, ... │
                           └──────────────────────▲────────────────────────┘
                                                  │
                                                  │ Executes Tool Calls
                                                  │
                           ┌──────────────────────┴────────────────────────┐
                           │          abstract class AgentProvider         │
                           │  - processUserPrompt(Context, prompt)         │
                           │  - Stream<AgentStep> streamResponse()         │
                           └──────────────▲─────────────────▲──────────────┘
                                          │                 │
                     ┌────────────────────┴───┐         ┌───┴───────────────────────┐
                     │     Open-Source Core   │         │    Proprietary Module     │
                     │     LocalSlmProvider   │         │     CloudAgentProvider    │
                     │                        │         │                           │
                     │ • On-device inference  │         │ • Authenticated to Server │
                     │ • llama.cpp / GGUF     │         │ • High-reasoning LLMs     │
                     │ • 100% offline         │         │ • Managed quota / sub     │
                     └────────────────────────┘         └───────────────────────────┘
```

### 3.1 The Abstract Agent Contract (In Open Source Core)

```dart
// lib/services/agent/agent_provider.dart

enum AgentProviderType { localSlm, cloudManaged }

abstract interface class AgentProvider {
  AgentProviderType get type;
  bool get isReady;
  
  /// Stream thought progression, tool calls, and final text response
  Stream<AgentEvent> processPrompt({
    required String prompt,
    required DocumentContext documentContext,
    required List<ToolDefinition> availableTools,
  });

  Future<void> cancelCurrentTask();
}

class DocumentContext {
  final int pageCount;
  final int currentPageIndex;
  final String? extractedPageText;
  final List<String> availableBookmarks;
  const DocumentContext({
    required this.pageCount,
    required this.currentPageIndex,
    this.extractedPageText,
    this.availableBookmarks = const [],
  });
}
```

### 3.2 Tool Calling & Schema Binding
The `TaskCatalog` (`lib/widgets/task_catalog.dart`) already provides machine-readable automation tasks:
- `page_rotate`, `page_delete`, `page_move`, `page_extract`
- `doc_redact_pattern`, `doc_ocr`, `doc_optimize`
- `form_fill`, `form_flatten`

The agent outputs a structured JSON tool call matching `TaskCatalog` schemas. The Flutter UI intercepts the tool call, displays a preview/confirmation sheet to the user, and upon approval dispatches it to `PdfEngineApi.applyOperation()`.

---

## 4. The Edge SLM Infrastructure (Open Source)

The local SLM runs 100% on the user's phone, requiring zero server infrastructure, incurring zero ongoing operational cost, and maintaining total privacy.

### 4.1 Recommended Mobile SLM Engines
1. **`llama.cpp` via Dart FFI / Flutter plugin (`flutter_llama_cpp`)**:
   - Best support for quantized GGUF format (Q4_K_M, Q3_K_M).
   - CPU + OpenCL/Vulkan/Adreno hardware acceleration.
2. **MediaPipe GenAI (Google)**:
   - Optimized for on-device Gemma models via MediaPipe Android/iOS task runners.
   - High performance on NPU / GPU delegates.

### 4.2 Target Models & Memory Budget
Mobile devices face strict thermal and RAM limits (especially devices with 6GB or 8GB of total RAM):

| Model | Quantization | Size on Disk | Target RAM | Recommended Task |
| :--- | :--- | :--- | :--- | :--- |
| **Qwen 2.5 1.5B / 3B** | Q4_K_M | 1.1 GB – 2.0 GB | ~1.5 GB | Fast document instruction following & tool JSON generation. |
| **Gemma 2 2B** | Q4_K_M | 1.6 GB | ~1.8 GB | High-quality text summarization and semantic Q&A. |
| **Phi-3.5 Mini (3.8B)** | Q3_K_M | 2.2 GB | ~2.5 GB | Complex reasoning and table extraction (requires 8GB+ RAM). |

### 4.3 On-Device Execution Safeguards
- **Model Download on Demand**: Do not bundle a 1.5 GB model into the base APK. Download weights optionally after first launch into app-support storage.
- **Low-Memory Fallback**: If device RAM < 6GB or memory pressure warning occurs, notify the user and throttle context length.
- **Background Isolate**: Always run SLM token generation in a dedicated background `Isolate` or native worker thread to prevent freezing the Flutter UI thread.

---

## 5. Cloud Inference Backend & Economics (Proprietary, No BYOK)

Because Overline supplies cloud inference without requiring user API keys (**No BYOK**), the server backend must act as an authenticated, quota-managed gateway.

```
┌─────────────────────────────────┐
│     Mobile App (Subscriber)     │
└────────────────┬────────────────┘
                 │ 1. Request with Firebase Auth JWT + encrypted prompt
                 ▼
┌─────────────────────────────────────────────────────────────────┐
│              Overline Cloud Inference Gateway (Private)         │
│                                                                 │
│ 1. Verify user authentication (Firebase Auth / Supabase Auth)   │
│ 2. Validate active subscription with Google Play Developer API  │
│ 3. Check monthly token budget & rate limits (Redis)             │
│ 4. Inject proprietary system prompts & few-shot context         │
│ 5. Audit & scrub sensitive tokens                               │
└────────────────┬────────────────────────────────────────────────┘
                 │ 2. Forward prompt to LLM
                 ▼
┌─────────────────────────────────┐
│   Cloud LLM Providers (SaaS)    │
│  (Gemini 1.5 Flash/Pro, Claude) │
└─────────────────────────────────┘
```

### 5.1 Financial Protection Principles:
1. **Never Call LLM APIs Directly from Mobile**:
   Never embed API keys or direct client endpoints in the app. Reverse engineers can extract keys within minutes.
2. **Subscription Verification**:
   The backend must verify subscription purchase tokens against the **Google Play Developer API** (or RevenueCat webhook) before forwarding any request.
3. **Token Quotas & Fair-Use Limits**:
   Each subscription tier includes a hard monthly token cap (e.g., 500,000 input tokens / month). Once exceeded, requests degrade gracefully to the on-device Edge SLM until the next billing cycle.

---

## 6. Repository Organization (Two-Repository Pattern)

To maintain a clean separation of open-source and proprietary assets, adopt the **Two-Repository Pattern**:

### Repository 1: `overline` (Public GitHub Repository)
- **License**: Apache License 2.0.
- **Contents**:
  - Full Flutter UI (manual viewer, annotator, page editor, form filler).
  - Rust engine bridge (`rust/`, `lib/bridge/`).
  - `LocalSlmProvider` on-device engine.
  - `TaskCatalog` and schema layers.
  - F-Droid / GitHub APK build configurations.
- **Community Role**: Open for bug reports, community contributions, translations, and third-party engine optimizations.

### Repository 2: `overline-app` (Private GitHub Repository)
- **License**: Proprietary / All Rights Reserved.
- **Contents**:
  - Contains `overline` as a Git submodule or imports it as a local path package.
  - `lib/pro/`:
    - `billing/`: In-app purchases, Google Play Billing, subscription listener.
    - `auth/`: User account authentication (Firebase Auth / Supabase).
    - `agent/`: `CloudAgentProvider` client adapter.
    - `paywalls/`: Premium feature comparison sheets and upgrade prompts.
  - `android/key.properties` and production release keystores.
  - Official brand icons, marketing imagery, and store fastlane configurations.
- **Output**: The official Google Play Store Android App Bundle (`.aab`).

---

## 7. Open-Source Licensing Strategy

1. **Why Apache 2.0 for the Open Core?**
   - Upstream `pdfcraft` is dual-licensed under **MIT / Apache-2.0**.
   - Apache 2.0 provides explicit patent rights grants and prohibits recipients from using your trademarks.
   - It is a **permissive license**: it legally allows you to link your proprietary commercial code (`overline-app`) against the open-source core without forcing the proprietary code to become open-source.
2. **Avoid GPLv3 / AGPLv3 for the Core**:
   - GPL is a "copyleft" license. If you license the core under GPLv3, anyone could legally compel you to open-source your proprietary billing, cloud client, and paywall code.

