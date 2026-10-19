# Phase 8: Google Play Store Closed Testing & Public Launch

**Target:** Prepare store marketing assets, complete Google Play Console compliance questionnaires, execute the mandatory 20-tester / 14-day closed testing track, and conduct a staged 5-day production rollout.  
**Prerequisites:** Phase 1 through Phase 7 complete.

---

## 1. Objectives & Deliverables
1. Prepare Google Play store assets (512×512 app icon, 1024×500 feature graphic, minimum 4 phone screenshots highlighting manual tools and hybrid AI features).
2. Complete Google Play Console declarations: Data Safety, Privacy Policy URL, Financial Features, and Content Rating.
3. Conduct the mandatory **20-tester, 14-day Closed Testing** track required for personal developer accounts created after Nov 13, 2023.
4. Apply for production release access with Google and answer review questionnaires.
5. Execute the phased 5-day staged rollout to 100% while actively monitoring Android Vitals SLOs.

---

## 2. Step-by-Step Implementation Instructions

### Step 8.1: Marketing & Store Visual Assets
Upload the following to **Google Play Console > Store presence > Main store listing**:
1. **App Icon**: 512 × 512 px PNG, 32-bit color, up to 1 MB.
2. **Feature Graphic**: 1024 × 500 px JPEG or 24-bit PNG (no alpha). Highlight: *"Overline: Private Offline PDF Editor + Edge & Cloud AI"*.
3. **Screenshots** (Minimum 4, 1080×2400 or 1440×3120):
   - Screenshot 1: *Fluid Reading & Smooth Pinch-Zoom* (Document viewer with dark theme).
   - Screenshot 2: *Mark Up, Annotate & Comment* (Highlighting, pencil, text notes).
   - Screenshot 3: *Fill & Sign Forms Securely* (Signature placement and form fields).
   - Screenshot 4: *Overline AI Assistant* (Agent command sheet showing on-device Edge SLM and Cloud Gemini Pro options).
4. **Copy Text**:
   - Title: `Overline: Fast PDF Editor & Signer` (from `fastlane/metadata/android/en-US/title.txt`).
   - Short description: Max 80 characters.
   - Full description: From `fastlane/metadata/android/en-US/full_description.txt`.

### Step 8.2: Google Play Console Compliance & Data Safety
1. **Privacy Policy**:
   - Enter your public HTTPS URL (e.g. `https://sujayganorkar.github.io/overline/privacy`).
2. **Data Safety Form** (Reference `docs/DATA_SAFETY.md`):
   - *Does your app collect user data?* Select **Yes** (only for subscription purchase tokens and anonymous crash logs; declare **No** for user documents and personal files).
   - *Are documents or PDFs uploaded to servers?* Declare that document manipulation is processed locally on-device, and cloud inference transmits temporary chunks solely when initiated by the subscriber, with zero permanent retention.
3. **Target Audience**: 18 and older (or General Audience without targeting children).

### Step 8.3: Closed Testing Management (The 14-Day Tester Requirement)
For personal developer accounts created after Nov 2023, Google enforces:
- **Minimum 20 testers opted in for at least 14 consecutive days**.
- Testers must remain enrolled and have the app installed on their devices.

#### Protocol:
1. Create a Google Group: `overline-closed-beta@googlegroups.com`.
2. Invite 25+ trusted colleagues, developers, or community members to join the group.
3. In Play Console, go to **Testing > Closed testing > Manage track > Testers**:
   - Add the Google Group email.
   - Copy the opt-in web link (`https://play.google.com/apps/testing/app.overline.pdf`).
4. Distribute the opt-in link to testers and confirm all 20+ testers install the build from Google Play.
5. **During the 14-day window**:
   - Verify active daily test sessions.
   - Test end-to-end subscription purchase sandbox.
   - Test Edge SLM offline mode vs Cloud Agent response quality.
   - Review crash logs in Sentry and Play Console Android Vitals.

### Step 8.4: Apply for Production Access
After 14 continuous days:
1. Google Play Console unlocks the **Apply for production** button.
2. Complete the 3-question survey:
   - *How did you recruit testers?* (e.g. Developer community, beta mailing list).
   - *How was the feedback collected?* (e.g. Google Forms, GitHub issues, in-app Diagnostics sheet).
   - *What feedback did you receive and what changes were made?* (Summarize bug fixes, UI adjustments, and performance optimizations made during beta).
3. Wait 24–72 hours for Google review approval.

### Step 8.5: Staged Production Rollout & Vitals Monitoring
Once production access is approved, **never roll out to 100% immediately**. Follow `docs/STAGED_ROLLOUT_PLAYBOOK.md`:

```
Day 1: 1% rollout   (~1,000–5,000 users)
Day 2: 5% rollout   (~25,000 users)
Day 3: 20% rollout  (~100,000 users)
Day 4: 50% rollout  (~250,000 users)
Day 5: 100% rollout (Full Release)
```

#### Android Vitals Thresholds (Immediate Halt Triggers):
| Metric | Target SLO | Google Play "Bad Behavior" Threshold | Action If Exceeded |
| :--- | :--- | :--- | :--- |
| **Crash Rate** | < 0.2% | **1.09%** | **Halt rollout immediately** |
| **ANR Rate** (Not Responding) | < 0.1% | **0.47%** | **Halt rollout immediately** |
| **App Startup Time (Cold)** | < 1,200 ms | > 5,000 ms | Review plugin initialization |

If an emergency bug occurs:
1. Halt rollout in Google Play Console with one click.
2. Use the remote kill switch in `FeatureFlagService` to disable any failing tool remotely.
3. Release hotfix build incrementing `versionCode`.

---

## 3. Post-Launch Maintenance Checklist
1. Monitor Sentry / Crashlytics dashboards daily for unhandled native Rust panics.
2. Monitor Redis token consumption across subscribers to detect prompt abuse or runaway token loops.
3. Maintain Google Play store review replies within 24 hours.
4. Triage open-source contributions in the public `overline` core repository.

