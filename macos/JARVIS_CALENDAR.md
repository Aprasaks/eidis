# JARVIS Calendar · Mac-native v3.14.12

This is a first-party JARVIS calendar, not an Apple/Google Calendar wrapper.

## Owner requirements

Six fields: (1) date, (2) start time, (3) optional end time, (4) title,
(5) place, (6) detailed notes. End time is **unknown** by default, never
silently set to one hour later. Title and start date/time are required.

## Opening and testing the real Mac app

- Menu bar `DECHIVE` icon → `JARVIS Calendar · 일정 관리`
- Or summon JARVIS (`⌘⌥J`), then type or say:
  - `자비스, 일정 보여줘` → opens native calendar (no writing)
  - `자비스, 내일 오후 3시에 회의 잡아줘` → pre-fills a draft editor; **Save** required
  - `일정 추가해줘` → blank editor, time/date confirmed by the owner
  - `일정 닫아줘` → closes the calendar overlay

Click a day to see stored schedules, select an event to edit/delete. Use
`새 일정` or `이날 일정 만들기` for manual entry. A successful save is shown
only after a confirmed 200 response from the local Mac calendar API and a
successful subsequent read. Errors are not converted into fake success.

## Data and local API

- Existing Mac JARVIS SQLite: `~/.jarvis-lab/memory.sqlite3`
- Table: `calendar_events` (UUID, ISO UTC timestamps, null `end_at`, explicit
  `deleted_at` tombstone, title/location/notes). Existing calendar records
  are preserved when migrating the original NOT NULL `end_at` column.
- API: `GET /api/calendar`, `POST /api/calendar/create`,
  `/api/calendar/update`, `/api/calendar/delete` (localhost-only port 8765).
- The original JARVIS private memory database is backed up to
  `~/Library/Application Support/JARVIS/Backups/` before deployment.
- Validation: end > start when present, duration <= 7 days, max title 120,
  place 200, notes 2000; explicit confirmation for destructive action.
- Named voice commands open read-only views or a draft; no audio-triggered
  write without the owner's Save button.

## Current limits

- JARVIS Calendar on iPhone v0.2.1 also supports unknown end time.
- **Mac ↔ iPhone synchronization is not implemented yet.** They currently
  have separate personal local data stores. No attempt is made to access
  phone data through the Mac loopback API, and vice versa.
- The Mac's SQLite backend is local-only, no WAN exposure, no third-party
  calendar import. Remote sync requires explicit owner pairing/authentication.
- Proactive reminders/automatic planning across devices are not yet enabled.

## Verification

- `swift build --package-path macos -c debug`
- `python3 -m unittest discover -s tests -p 'test_*.py' -q`
- `swiftc -parse-as-library macos/Sources/EidisMac/JarvisMacCalendar.swift macos/tests/calendar-intent/StandaloneNearbyStub.swift macos/tests/calendar-intent/main.swift -o /tmp/jarvis-calendar-mac-intent-tests && /tmp/jarvis-calendar-mac-intent-tests`
- Open the actual JARVIS Calendar menu on the connected Mac and inspect the
  custom month grid and form at its native window size.

## Nearby sync (Mac v3.14.13 / iPhone v0.3.0)

- In Mac Calendar, press `iPhone 연결`; a **fresh 12-digit, 10-minute code**
  appears. In iPhone Calendar, press the chain/link icon, choose the correct
  `JARVIS Mac`, enter the code, and complete pairing.
- No calendar content is transferred until **both** devices verify keyed
  HMAC-SHA256 proofs, using two random nonces. The code itself is not sent.
  Transport uses `MultipeerConnectivity.MCSession` with encryption required.
- The Mac HTTP API remains **loopback only**; no public HTTP sync service.
- The Mac SQLite database is the canonical merge authority. iPhone keeps an
  offline JSON copy, pending change IDs, and exact Mac `updatedAt` tokens.
  Conflicting edits are **not overwritten**; iPhone keeps its local pending
  record and shows the conflict count, for manual resolution later.
- Changes saved on the Mac notify the paired iPhone; the iPhone syncs when
  first paired, manually requested or resumed in the foreground.
- Pairing is intentionally temporary, not automatic across restarts. A new
  code is needed after the secure session is disconnected.
- Both apps show only calendar-related states; the phone has a simplified
  home, dashboard and calendar layout. Physical two-device pairing is the
  final live acceptance test, distinct from unit/compilation tests.
