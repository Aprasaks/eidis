# Command Center / left column layout
- Main overview left column is Project Operations, META, YouTube in that order. Replaces the Git/local Git card only in the left-column UI, preserving Git and GitHub scanners and summary metric elsewhere; no deletion of credentials or data.
- META card reuses the existing read-only fixed DECHIVE.WIKI Instagram Graph API and Keychain connection form; Facebook and Threads show explicit "API 연동 전 · 실시간 자료 없음" rather than fabricated statistics or assuming Instagram credentials cover them.
- YouTube now has its own card using the existing channel analytics, authentication UI and source state; no new API permissions or network calls.
- Central foreground core, right conversation/Mac telemetry, independent card scrolling and fixed screen sizing remain unchanged. Regresion tests: 315. Hardware screenshot to verify after packaging.
