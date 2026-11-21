# DECHIVE THINKING CORE 1.1 — Continuity
2026-11-21

## Scope and rules
- Local Python server runs an initial review before accepting HTTP requests and repeats checks roughly every 60 seconds while serving requests. Mac sleep/shutdown or a busy server may delay checks.
- This is deterministic evidence monitoring, not independent LLM reasoning. No background Qwen call, paid API, network request, microphone capture, advertising or external publishing.
- Existing SQLite project tasks: blocked status gets an alert; non-completed tasks with no record update for 72 hours get a check-in alert. This is NOT proof of a missed task or overdue deadline.
- Saved, unreviewed hypotheses: check after 24 hours, and compare fingerprints of relevant local memory/vault/project search results. Review up to 24 hypotheses per scan, oldest checked first. Other thought records are excluded as evidence; existing source status is preserved. Search result changes are a prompt for human review, not proof of a hypothesis being right or wrong.
- Additive tables: continuity_alerts, continuity_watch, continuity_meta. No automatic changes to task or thought status, no raw conversation retention. One alert per source; unchanged alerts remain acknowledged across restarts. Changed evidence may reopen an alert. Completed tasks and reviewed/rejected hypotheses resolve their alerts on the next scan.
- Local read endpoint: GET /api/continuity; explicit acknowledge: POST /api/continuity/acknowledge. Both inherit same-origin/loopback checks. Acknowledgement does NOT complete a task or verify a hypothesis.
- During summoned dialogue, refresh a small read-only notification line every 30 seconds. Existing mic, TTS, core animation, settings-free layout and model call remain unchanged.
- Natural queries: "자비스, 내가 까먹은 일 있어?", "자비스, 다시 검토할 것 알려줘", "자비스, 알림 3번 확인했어". The report describes up to three open alerts and the total. No unsolicited spoken alert, OS notification permission or external message.
- The subsystem is built on the current local store; no iPhone sync, always-on service or model training yet. Next phase: bounded, interruptible local-Qwen study jobs with separate evidence and hypotheses, without delaying live dialogue.

## Verification
- New tests exercise periodic HTTP scan, same-origin rejection, persisted acknowledgement, changed evidence, automatic resolution, age threshold and no unauthorized fact promotion.
- Full Python suite: 230 tests passed. Swift intent smoke test: passed. Previous Mac Swift build: passed; packaged build and installation verified separately.
- Existing live microphone / ElevenLabs behavior still needs real-user check.
- Pre-upgrade local SQLite backup: ~/.jarvis-lab/backups/pre-continuity-core-20261121.sqlite3 (0600). Existing app backed up separately during installation.
