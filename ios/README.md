# JARVIS Mobile — iPhone v0.1

This is the first **real native iPhone companion app** in the active
`JARVIS-FULLSCREEN-PREVIEW` project. It is separate from the older
`JARVIS-EIDIS-v03/v04` prototypes and does not replace the installed Mac app.

## Verified first build

- iPhone UI written in SwiftUI, black/gold visual design and the same golden
  app icon as Mac JARVIS.
- The **exact animated golden core from the active Mac fullscreen JARVIS overlay**
  (`macos/Resources/Art/DECHIVE_FullHD_Loop.mp4`), displayed as a local,
  muted, looping video. The mobile video crops only the central 920x920 pixels
  of the original 1920x1080 H.264 film, to hide the film-baked footer and
  preserve the full golden orbit without stretching. It is not the unrelated
  SceneKit prototype. Playback pauses when backgrounded or Reduce Motion is on.
- Explicit microphone button with Apple on-device Korean speech recognition,
  local text input, and system Korean text-to-speech (using existing iPhone
  voice module).
- A small and **deterministic offline intent router**; no cloud AI reasoning
  API and no required subscriptions. ElevenLabs voice output is **optional**
  and may consume ElevenLabs credits when explicitly enabled.
- Mac status and stock shortcuts explain that pairing is not yet implemented;
  no sample portfolio, fictitious Mac online state, or fake remote commands.
- Bundle identifier: `dev.dechive.jarvis.mobile` (does not overwrite earlier
  iOS prototype `dev.dechive.jarvis.ios`).

## Running in Xcode

Open `ios/JARVIS.xcodeproj`, select the JARVIS scheme, choose an available
iPhone simulator, and Run. From the shell, e.g.:

```sh
xcodebuild -project ios/JARVIS.xcodeproj -scheme JARVIS -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath /tmp/jarvis-mobile-derived \
  CODE_SIGNING_ALLOWED=NO build
```

Run local intent assertions (independent of simulator):

```sh
swiftc -parse-as-library ios/JARVIS/Sources/JARVISCommand.swift \
  ios/JARVISTests/main.swift -o /tmp/jarvis-mobile-intent-tests
/tmp/jarvis-mobile-intent-tests
```

Simulator screenshots: `ios/screenshots/JARVIS_v01_iPhone17Pro_simulator.png`
and `ios/screenshots/JARVIS_v01_iPhone13_simulator.png` show the initial
prototype. The corrected original-core appearance is in
`ios/screenshots/JARVIS_v011_iPhone13_actual_mac_core.png`. Both iPhone 17 Pro
and iPhone 13-size simulators built, installed and launched successfully.

## Explicit limitations

- **No Mac pairing/remote execution yet.** UI reports disconnected truthfully.
  Next: authenticated encrypted Mac-to-iPhone connection with explicit
  allowlisted commands and verified responses (do not expose raw shell).
- No real-time market prices or real device data in this mobile app yet.
- The microphone is **not** an always-on iPhone background wake word.
  On-device Korean speech recognition depends on actual device availability
  and user-approved microphone/speech permissions. The Simulator does not
  validate real microphone STT quality.
- The actual iPhone 13 was successfully paired/visible on 2026-11-23.
  The iPhoneOS **signed development build succeeded**, but the attempt to
  install to the physical device failed during the developer disk image
  mount because the phone was locked (`kAMDMobileImageMounterDeviceLocked`).
  The physical app was **not installed**. Unlock the iPhone and retry; runtime
  compatibility and on-device behavior still require verification.
- The core is the original **rendered video used by the Mac fullscreen overlay**,
  not native iPhone SceneKit geometry. No separate Blender model is included
  in this stage. Test playback performance and loop seamlessness on the real phone.

## Workflow

1. Build and visually verify the iPhone app and its **original Mac video core**.
2. Validate on the user's actual iPhone, including native permissions.
3. Add encrypted pairing with the running Mac JARVIS and a truthful online/offline indicator.
4. Bring over read-only stock/project dashboards.
5. Add remote actions one-by-one with approval and actual completion evidence.

## Video reproducibility

The iPhone crop is produced by this command and must stay visually identical
to the original Mac 10-second animation (except square framing):

```sh
ffmpeg -i macos/Resources/Art/DECHIVE_FullHD_Loop.mp4 \
  -vf 'crop=920:920:500:0' -an -c:v libx264 -preset medium -crf 19 \
  -pix_fmt yuv420p -movflags +faststart \
  ios/JARVIS/Resources/DECHIVE_Core_Mobile.mp4
```

## iPhone-only address and voice (v0.1.3)

- Since 2026-11-28 the assistant is EIDIS (이디스) on both iPhone and Mac, and it
  always addresses the owner as **DECHIVE** (spoken 데카이브).
- The waveform button at the top opens an opt-in **ElevenLabs** settings
  sheet; default TTS is still the built-in iOS Korean voice.
- Voice ID and model default to the currently configured Mac values
  (Voice ID `6Vgh4FaCc0SCcWPwcyXa`, model `eleven_flash_v2_5`).
  Voice IDs are not secrets; ElevenLabs API keys are secrets.
- The Mac's `ThisDeviceOnly` Keychain credential **cannot be read by iPhone**.
  For the owner's private development build only, the user may explicitly
  paste a key into iPhone's secure settings; the key is saved to the iPhone
  Keychain (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`), never shipped
  or logged. A separate opt-in toggle controls any paid synthesis.
- Metadata-only voice access checks don't generate audio. Ordinary TTS POST
  requests consume credits depending on the user's ElevenLabs account.
  Requests are limited to 600 characters, don't retry automatically, and
  fall back to built-in iOS TTS on failures. No TTS request is made by
  launching the app or by opening settings.
- **Before public distribution** replace direct iPhone ElevenLabs API calls
  with a paired Mac proxy or short-lived server-minted credentials. Long-lived
  API keys on client devices are not appropriate for a distributed app.
- API playback has NOT been verified with a real key / account in this stage.
  iOS simulator tests establish the code compiles, not provider access.

## Mobile control center (v0.1.4)

- Bottom tabs: **코어**, **전체 현황**, **일정**, **기억**. These views can
  also be opened via voice/text, e.g. “전체 대시보드 열어줘”, “일정 보여줘”,
  “기억 보여줘”, “주식 현황표 열어봐”.
- The dashboard has **8 named panels**: schedule, memory/profile, stock board,
  projects, knowledge vault, SNS, news, and Mac system status. These mirror
  real features/sources that exist on the Mac; they do NOT pretend to be
  synchronized or show synthetic data.
- **Historical v0.1.4 note only**: this version read Apple Calendar. In v0.2.0
  it has been replaced by the native, persistently stored JARVIS Calendar.
  See the v0.2.0 section below for the current behavior.
- **Memory, stock, projects, knowledge, SNS, news, and system remain Mac
  disconnected**. They have explicit state screens, not invented numbers or
  guessed project/event names. Next stage is authenticated Mac pairing and a
  read-only, allowlisted API with truthful request results and timestamps.
- The original golden video and ElevenLabs voice settings remain unchanged.
  Normal startup still opens the original core; only simulator debug launch
  argument `--jarvis-mobile-preview=dashboard` (or any page raw value) opens
  a specific page for visual verification.
- Current simulator screenshots are `ios/screenshots/JARVIS_v014_iPhone13_*.png`.
  Physical iPhone calendar permissions and actual spoken intent remain to be
  validated on the user's device after installation.

## JARVIS native Calendar v0.2.0 — replaces the old EventKit read-only view

**This is NOT the iPhone / Apple Calendar.** Its data originates in JARVIS:

- Calendar tab displays a month grid and actual saved JARVIS appointments;
  select a date or press **+** to create a new appointment.
- Add/edit/delete persists under this app's own Application Support directory
  at `JARVIS/calendar-v1.json` with atomic writes, UUID identifiers, ISO 8601
  UTC timestamps, and deletion tombstones for future synchronization.
- Title, dates, location and optional notes are user-editable; end time must
  follow start time. Overlaps are shown before saving. Damaged JSON files
  are **not** overwritten.
- Optional iPhone local notifications (start, 10, 30 or 60 minutes before),
  with explicit system authorization. A successful calendar save is NOT
  misrepresented as successful reminder registration; the two have separate
  status checks.
- Voice/text creation example: `자비스, 내일 오후 3시에 회의 잡아줘`.
  JARVIS parses only supported, unambiguous Korean date/time expressions,
  opens a populated confirmation editor, and **does not write until the user
  presses Save**. Missing/ambiguous details open the manual editor instead.
- No existing Apple Calendar entries are imported, and no Apple calendar
  permission is requested. No sample events are shown as genuine entries.
- Mac JARVIS has a new, additive local SQLite calendar table and localhost
  REST endpoints under `/api/calendar`, plus `/api/calendar/create`,
  `/api/calendar/update`, `/api/calendar/delete`. They use the same independent
  schedule schema, but are NOT currently connected to the iPhone calendar.
- The Mac backend source has tests but the previously installed Mac v3.14.10
  has **not** been rebuilt or replaced during this step.

**Important unfinished work**: encrypted/authenticated sync with a common
owner-controlled backend, authenticated remote access when the Mac is off,
conflict reconciliation, a native Mac calendar surface, and automatic proactive
planning/briefing. Don't claim that iPhone events already appear on Mac.

Tests:

```sh
swiftc -parse-as-library ios/JARVIS/Sources/JARVISCalendarDomain.swift \
  ios/JARVISTests/calendar-domain.swift -o /tmp/jarvis-calendar-domain-tests
/tmp/jarvis-calendar-domain-tests
swiftc -parse-as-library ios/JARVIS/Sources/JARVISCalendarDomain.swift \
  ios/JARVIS/Sources/JARVISCalendarStore.swift ios/JARVISTests/calendar-store.swift \
  -o /tmp/jarvis-calendar-store-tests
/tmp/jarvis-calendar-store-tests
python3 -m unittest discover -s tests -p test_jarvis_native_calendar_v1.py -q
```

### v0.2.1 · Unknown end time

The shared JARVIS schedule concept uses six core fields: date, start time,
**optional** end time, title, place and details. The mobile calendar editor
now defaults to `종료시간 미정` (end is truly null), without assuming a one-hour
appointment. The natural-language Korean parser also creates a draft with
an unknown end time. Existing records with a known end remain readable.
This update does NOT connect the phone to the Mac server yet.

### v0.3.0 · Nearby Mac calendar sync + clean screens

- Core/home: preserved golden Mac animation; removed the repetitive LOCAL,
  subtitle, help copy, and redundant dashboard rows. Calendar: no repeated
  "iPhone only", "Mac not connected", developer explanations or imported
  Apple Calendar references. Essential errors and sync conflicts still show.
- Link icon in Calendar opens Mac pairing: find a nearby JARVIS Mac, enter
  its **12-digit temporary code**, wait for mutual device proof, then sync.
- End-to-end sync uses encryption-required Multipeer Connectivity, client and
  server nonces plus HMAC-SHA256 bidirectional proof. The PIN is never sent
  in invitation context or any sync message. Mac port 8765 stays on loopback.
- iPhone edits work offline; pending IDs and exact Mac versions persist on
  device in schema 2. After pairing, pending edits are submitted with Mac
  revision checks. Mac returns an authoritative snapshot including deletions.
- On a conflict, iPhone local changes remain intact and are flagged rather
  than silently overwritten; explicit conflict resolution UI remains future
  work. iPhone reminders remain local.
- **Not Internet/cloud sync**. Paired devices should be nearby with local
  network permissions. If Mac is off, iPhone can still view/edit its local
  calendar and queue changes for the next pairing.

### v0.4.0 · Native JARVIS Alarm

- Added the native `알람` tab and gold-core shortcut. JARVIS creates its own
  iOS 26+ AlarmKit alarms with system authorization and verification.
- One-shot and selected weekly repeat, edit, disable, delete, and a
  user-confirmed short alarm test are available.
- No Apple Clock events are read or altered. No alarm is automatically
  scheduled by installation, app launch, or a voice command alone.
- The lock-screen alarm -> greeting -> news -> calendar morning routine is
  planned but NOT implemented by this first standalone alarm build.
- Exact design, manual acceptance steps and limitations: `ios/JARVIS_ALARM.md`.
