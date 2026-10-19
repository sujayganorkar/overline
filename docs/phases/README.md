# Overline: Master Execution Blueprint

This directory contains the complete, phase-by-phase implementation specifications for transitioning **PdfCraft Mobile** into **Overline**, building out the open-core Edge SLM and proprietary cloud inference features, and executing the commercial release on Google Play.

Every phase specification is authored to be **fully autonomous and agent-executable**: containing exact file paths, code implementations, bash commands, verification criteria, and edge cases.

---

## Phase Execution Sequence

```
[Phase 1: Rebranding & Legal Foundation]
       │ (Package identity, legal compliance, 16KB alignment)
       ▼
[Phase 2: Manual Tool Parity & Hardening]
       │ (Audit all engine operations, touch UI sheets, OOM tests)
       ▼
[Phase 3: Unified Agent Layer & Edge SLM]
       │ (AgentProvider interface, TaskCatalog tool-calling, local GGUF SLM)
       ▼
[Phase 4: Cloud Inference Backend]
       │ (Private gateway, auth, LLM streaming, token budgeting)
       ▼
[Phase 5: Billing, Subscriptions & Cloud Client]
       │ (Google Play Billing, receipt validation, CloudAgentProvider)
       ▼
[Phase 6: Repository Separation & CI/CD]
       │ (FOSS Core vs Commercial App repos, automated pipelines)
       ▼
[Phase 7: Production Signing & Observability]
       │ (Upload keystores, Crashlytics/Sentry sink, remote kill-switch)
       ▼
[Phase 8: Closed Testing & Staged Rollout]
       │ (20 testers for 14 days, Android Vitals SLO, 1% -> 100% rollout)
       ▼
[Public Production Launch]
```

---

## Phase Documents Index

| Phase | Specification Document | Key Deliverables |
| :--- | :--- | :--- |
| **Phase 1** | [`PHASE_1_REBRANDING_AND_LEGAL.md`](file:///home/sujay/Downloads/pdfcraft-mobile/docs/phases/PHASE_1_REBRANDING_AND_LEGAL.md) | Package rename to `app.overline.pdf`, Kotlin migration, Dart import replacements, UI copy, Open Source Licenses screen, 16KB ELF alignment. |
| **Phase 2** | [`PHASE_2_MANUAL_TOOL_PARITY_AND_HARDENING.md`](file:///home/sujay/Downloads/pdfcraft-mobile/docs/phases/PHASE_2_MANUAL_TOOL_PARITY_AND_HARDENING.md) | Parity audit with Rust engine operations, touch sheets for all tools, LRU memory profiling, SAF recovery invariants. |
| **Phase 3** | [`PHASE_3_UNIFIED_AGENT_AND_EDGE_SLM.md`](file:///home/sujay/Downloads/pdfcraft-mobile/docs/phases/PHASE_3_UNIFIED_AGENT_AND_EDGE_SLM.md) | `AgentProvider` contract, `TaskCatalog` schema-to-tool converter, local SLM runtime (`llama.cpp`), model weight downloader, UI chat sheet. |
| **Phase 4** | [`PHASE_4_CLOUD_INFERENCE_BACKEND.md`](file:///home/sujay/Downloads/pdfcraft-mobile/docs/phases/PHASE_4_CLOUD_INFERENCE_BACKEND.md) | Private gateway service (FastAPI/Go), Firebase/Supabase Auth, LLM streaming (Gemini/Claude), token quotas, Redis rate limiting. |
| **Phase 5** | [`PHASE_5_BILLING_SUBSCRIPTIONS_AND_CLIENT.md`](file:///home/sujay/Downloads/pdfcraft-mobile/docs/phases/PHASE_5_BILLING_SUBSCRIPTIONS_AND_CLIENT.md) | Google Play Billing, server receipt validation, `CloudAgentProvider` client adapter, paywalls, quota fallback. |
| **Phase 6** | [`PHASE_6_REPO_SEPARATION_AND_CICD.md`](file:///home/sujay/Downloads/pdfcraft-mobile/docs/phases/PHASE_6_REPO_SEPARATION_AND_CICD.md) | Two-repo architecture (`overline` public FOSS vs `overline-app` private commercial), GitHub Actions CI/CD workflows. |
| **Phase 7** | [`PHASE_7_PRODUCTION_SIGNING_AND_HARDENING.md`](file:///home/sujay/Downloads/pdfcraft-mobile/docs/phases/PHASE_7_PRODUCTION_SIGNING_AND_HARDENING.md) | Production upload keystore (`upload-keystore.jks`), Google Play App Signing, crash telemetry sink, remote feature flags. |
| **Phase 8** | [`PHASE_8_PLAY_STORE_TESTING_AND_LAUNCH.md`](file:///home/sujay/Downloads/pdfcraft-mobile/docs/phases/PHASE_8_PLAY_STORE_TESTING_AND_LAUNCH.md) | Store graphics, Data Safety submissions, 20-tester / 14-day tracking, Android Vitals SLO monitoring, 5-day staged rollout. |

