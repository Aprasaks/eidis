# JARVIS Mac v3.7 — Cinematic Native Home

## What changed

Mac JARVIS now opens to a native dark console, not the automatically shown web dashboard. A briefly animated SwiftUI circular core and two verified status indicators appear before the practical home. This is not a prerecorded movie or a fake system-activation sequence.

- **Launch intro**: black / restrained cyan, native rotating rings, automatic home reveal after around 2.3 seconds, respects macOS Reduce Motion. Server/memory indicators change only from verified state. Offline still allows access to Diagnostics.
- **Native home**: localhost server readiness, verified local project-list response, counts of recorded pending/in-progress/completed/blocked tasks, first recorded in-progress task (or pending), Korean TTS voice selection and Apple local-model availability. No claim of active microphone input.
- **Commands**: Work, Voice, Screen, Diagnostics, Refresh navigate to existing features or refresh read-only state; no permission prompt, file modification or task execution on launch.
- **Legacy web console**: accessible from the new home via “기존 자비스 콘솔 열기”; server detail and Mac voice preview are preserved in that area.
- **No new data writes**: no task status updates, Git/AWS actions, file edits, paid AI calls, camera or mic starts.

## State-truthfulness rules

- The SERVER indicator is online only after the application's own checked localhost identity/health response.
- MEMORY counts are hidden until a real successful /api/projects response. A failed fetch does not confirm the memory.
- Next task selection uses saved in-progress records first, otherwise pending records. It does not claim completed development or verified deployment.
- VOICE means an on-device Korean speech synthesis voice is selectable, not that voice recognition has been physically tested.
- LOCAL AI reflects OS model availability only, not a claim of general reasoning or scene understanding.

## Verification and limitations

- Mac native SwiftUI app compiled with Swift Package Manager.
- Native offscreen visual smoke tests rendered the launch intro, dashboard and offline state at desktop dimensions.
- Screenshots under docs/screenshots use entirely **synthetic project names and task counts**, never the owner's personal DB data.
- Python regression checks verify that all original tabs and important controls remain.
- Actual installation, live app-server pairing and real user screen interactions are separate verification stages.
- Login-at-boot auto-start is not enabled. The installed JARVIS.app still starts its bundled localhost Python companion per v3.6.

## 3.7.1 startup hotfix

Actual installed 3.7.0 app initially opened a process but did not complete the localhost server startup. A live stack sample showed macOS Keychain lookup for the stored ElevenLabs key blocked the SwiftUI main thread. 3.7.1 moves **automatic key availability lookup to a detached utility task** so the UI/server can start without unlocking the keychain; opting in to paid TTS remains explicit. A revision guard avoids overwriting a key the user changes while a background check is pending. Existing credentials are neither read into logs nor deleted. Recheck real installed startup after packaging; build alone does not prove the fix.

## Actual Mac installation and verification — 2026-11-18 KST

- The first v3.7.0 build compiled/installed but **did not complete startup**. A live stack sample of the hung app found `ElevenLabsVoiceService.init` synchronously blocked on `SecItemCopyMatching` from macOS Keychain. It was not a successful app/server test.
- Fixed in **JARVIS 3.7.1 (build 38)**: Keychain availability checks now run off the SwiftUI main thread, with user key mutation revision protection. No API key was exported or deleted and ElevenLabs paid requests remain opt-in.
- Python regression suite **129 tests passed**; native SwiftUI project compiled, and offscreen render of native intro/home/offline states succeeded. Screenshot fixtures in this directory are synthetic UI samples, **not actual user project data**.
- Existing JARVIS 3.6 app and SQLite database were backed up before install. JARVIS 3.7.1 was packaged, ad-hoc signed, signature verified, and installed by replacing only `~/Applications/JARVIS.app` with the same bundle identifier.
- **Live physical Mac validation passed**: installed JARVIS window appeared; its own local Python server was launched as a child process, with HTTP 200 from `127.0.0.1:8765/api/diagnostics` and two saved projects visible from the real project list. macOS window capture visually confirmed the dark JARVIS v3.7 dashboard.
- User data preserved: SQLite `PRAGMA quick_check = ok`, 2 projects, 25 task records (11 todo, 14 done) unchanged after installation.
- This does not prove the voice mic, capture permission, or each button's physical click flow has been manually retested in v3.7.1. The app is currently running on the Mac; login-at-boot autorun remains unimplemented.
