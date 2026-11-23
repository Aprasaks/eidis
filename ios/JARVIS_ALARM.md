# JARVIS Alarm · First native morning alarm

This is NOT an Apple Clock/Calendar wrapper. iPhone JARVIS directly schedules
its own system-level alarm using Apple's AlarmKit (iOS 26+).

## What was implemented (v0.4.0, build 9)

- A dedicated `알람` tab and a shortcut on the JARVIS gold-core home screen.
- Add/edit a wake-up alarm: local time, label, one-time or selected weekdays.
- `평일`, `매일`, and manually chosen repeated weekdays.
- Enable or disable a saved alarm and delete it. Deletion cancels the matching
  system AlarmKit alarm and does NOT change the Apple Clock app's alarms.
- A `3분 뒤 시험 알람` shortcut **opens an editor** at approximately 3 minutes
  in the future; the user MUST explicitly press `저장`.
- For first-time authorization, the user MUST approve JARVIS alarm access on
  the physical iPhone. The system alarm is checked after scheduling; errors
  do not show false success or silently create pretend local entries.
- An atomic, private JSON ledger at `Library/Application Support/JARVIS/alarms-v1.json`.
  If the ledger cannot be decoded, existing data is preserved and editing
  stays blocked until recovered.
- Text/voice `알람 맞춰줘`, `자비스 알람 열어줘` open the alarm editor/view.
  No spoken request can schedule an alarm without explicit `저장`.
- One-time schedule uses an absolute next local occurrence; repeating weekly
  alarms use AlarmKit relative recurrence, which adjusts to the time zone.
- Initial alarms use system default alarm sound and a native system stop
  control; there is **no** artificial countdown or dummy alarm sound.

## Live acceptance test

1. Update JARVIS on iPhone 13 (do not uninstall the old app).
2. Open `알람` → `3분 뒤 시험 알람` → verify time → `저장`.
3. On the first attempt, approve the iOS AlarmKit permission.
4. Verify the alarm is listed and enabled. Lock the device and wait until
   the appointed time, then test actual alert, sound and Stop.
5. Open JARVIS again: check the alarm's system status; test disable/delete.
6. Optional: create a weekday 7:00 AM alarm only after the short test passes.

Current explicit limitations:

- A lock-screen Stop does **not yet** auto-play the spoken "애기" greeting.
  That needs a separate App Intent/foreground launch test and opt-in.
- Snooze is not yet enabled because reliable countdown presentations need a
  proper Widget/Live Activity integration. Do not claim it already works.
- News briefing and morning schedule reading are not yet connected to the
  alarm trigger. This iteration creates the actual alarm base first.
- AlarmKit permission and actual locked-screen alarm firing require a human
  to validate on the real iPhone; a compile or simulator is insufficient.

## Verification commands

```sh
swiftc -parse-as-library ios/JARVIS/Sources/JARVISAlarmDomain.swift \
    ios/JARVISTests/alarm-domain.swift -o /tmp/jarvis-alarm-domain-tests
/tmp/jarvis-alarm-domain-tests
python3 -m unittest discover -s tests -p 'test_*.py' -q
xcodebuild -project ios/JARVIS.xcodeproj -scheme JARVIS \
    -configuration Debug -sdk iphonesimulator \
    -destination 'platform=iOS Simulator,name=JARVIS v02 Layout iPhone 13' \
    -derivedDataPath /tmp/jarvis-mobile-01-derived CODE_SIGNING_ALLOWED=NO build
```

## v0.4.1 · "일어났어" confirmation action

Apple AlarmKit owns the **system stop/X** control starting iOS 26.1.
Its old `stopButton` presentation property is deprecated and ignored by the
system; consequently it is impossible to remove or rename this stop/X in the
system alert using AlarmKit's public API.

JARVIS therefore adds a **separate** `일어났어` secondary alert action with
`secondaryButtonBehavior: .custom` and a `LiveActivityIntent`. Pressing it
attempts to stop the ringing AlarmKit alarm. **Only after a successful stop**
does it record a local wake acknowledgement timestamp and the exact alarm UUID
in JARVIS preferences. The app displays a brief `기상 확인 완료` status when it
is opened on the same day. It does not falsely treat an ordinary system X/stop
as an affirmative wake acknowledgement.

This secondary button is a real system alert action, not a mock overlay.
Because the alarm presentation is recorded when AlarmKit schedules the alarm,
**pre-existing scheduled alarms must be re-saved (edit → save), or a fresh
trial alarm must be created, before the new action is visible**. The app
does not silently cancel/reschedule the owner's existing alarms during upgrade.

Pending physical checks: whether the iPhone displays the secondary action,
its title and stop effect while locked, whether App Intents background/foreground
behavior leads to the desired experience, and whether the acknowledgement
persists reliably. We do not claim that a future spoken greeting or news
briefing is already implemented.
