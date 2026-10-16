# Google Play Console Data Safety Questionnaire Guide

Use the answers below when completing the **Data Safety** section in Google Play Console for **PdfCraft Mobile**.

---

### Data Collection and Security Overview

| Question | Answer | Notes |
| :--- | :--- | :--- |
| **Does your app collect or share any of the required user data types?** | **No** | PdfCraft Mobile operates 100% offline for all document manipulation. No user documents or PII are sent to any server. |
| **Is all user data collected by your app encrypted in transit?** | **N/A** (No data collected/transmitted) | Cleartext traffic is blocked at OS level via `android:usesCleartextTraffic="false"`. |
| **Do you provide a way for users to request that their data is deleted?** | **Yes** | All data (signatures, recent documents, settings) resides locally on-device and can be cleared via app settings or OS App Info -> Clear Data. |

---

### Specific Data Type Declarations

| Category | Data Type | Collected? | Shared? | Purpose |
| :--- | :--- | :--- | :--- | :--- |
| **Location** | Approximate / Precise | No | No | None |
| **Personal Info** | Name, Email, User IDs, Address, Phone, etc. | No | No | None |
| **Financial Info** | Payment info, Purchase history, Credit score | No | No | None |
| **Health & Fitness**| Fitness, Health records | No | No | None |
| **Messages** | Emails, SMS, in-app messages | No | No | None |
| **Photos & Videos** | Photos, Videos | No | No | None |
| **Audio Files** | Voice recordings, Sound files | No | No | None |
| **Files & Docs** | Files and documents | **No** (Processed locally on-device only) | No | Files are opened locally in sandbox memory and are never uploaded. |
| **Calendar** | Calendar events | No | No | None |
| **Contacts** | Contact details | No | No | None |
| **App Activity** | Page views, taps, actions | No | No | No third-party tracking or advertising SDKs. |
| **Web Browsing** | Web browsing history | No | No | None |
| **App Info & Perf** | Crash logs, Diagnostics | Optional (Only if user manually exports diagnostic log) | No | Breadcrumbs reside in ephemeral RAM; never automatically uploaded to any endpoint. |
| **Device IDs** | Device or other IDs | No | No | No advertising IDs (AAID/IDFA) used. |

---

### Permissions & Android Manifest Security Posture

- `android:allowBackup="false"` prevents unencrypted cloud backups of user PDFs, annotations, and signatures to third-party Google drive backups.
- `android:usesCleartextTraffic="false"` enforces HTTPS for any outbound network connections.
- Persistable URI permissions (`FLAG_GRANT_READ_URI_PERMISSION`) ensure least-privilege access to user-selected documents without broad filesystem scanning.
