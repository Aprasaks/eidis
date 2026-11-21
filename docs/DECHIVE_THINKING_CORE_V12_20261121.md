# DECHIVE THINKING CORE 1.2 — Autonomous local study
2026-11-21

## Purpose
Continue explicitly delegated topics without asking for a thinking mode. Revisit when the eligible local evidence changes; preserve hypotheses and proposals separately from facts.

## Implemented
- Persistent SQLite study_topics, study_jobs, study_runs, study_settings. Existing data unchanged.
- Explicit ongoing delegation, e.g. "그거 나중에 더 생각해봐" or "광고 전략 계속 연구해줘". The first uses the prior discussion, the second records the named topic. Ordinary dialogue does not register a topic. Negation/question guard; the Korean parser is still rule-based and not comprehensive.
- Initial job on delegation; continuity scheduler revisits the topic when the relevant local evidence fingerprint changes, approximately every minute while the app server runs. User-supplied/saved notes and local project records only; no other assistant hypotheses or unverified web sources as evidence. Retrieval is limited lexical search and excerpts, not external research or exhaustive verification.
- 24 active topics maximum. Rolling 24-hour cap of 3 claimed runs, 1 concurrent run, 2 attempts per job. Interrupted/failed work can retry after 5 minutes within that cap. Lease expires after 150 seconds for crash recovery. Same evidence revision deduplicated.
- Mac runner uses fixed loopback Ollama qwen3.5:9b-q4_K_M, non-thinking mode, bounded context/output, no tools, no remote model/paid API. Polls every 20 seconds, waits at least 20 seconds after dialogue closes; skips on low power or serious/critical thermal state. Summon immediately cancels the background request and prevents new study while the fullscreen dialogue is visible. Ollama cancellation speed itself is not guaranteed or measured; actual foreground latency under interruption still requires hardware testing.
- Store completed outputs as ai_generated_unverified drafts, including exact captured evidence refs/excerpts and date. New evidence can produce a new draft; prior drafts remain available by number. Do not promote to facts, change project status, execute generated code, publish, spend money, or access the network.
- Dialogue screen displays completed draft count from actual local data. No automatic spoken interruption. Use "혼자 생각한 것 알려줘" or "연구 현황 알려줘", "검토 초안 1번 보여줘". "자동 사고 멈춰"/"자동 사고 재개해" persists the global permission; "연구 주제 1번 중단해" disables that topic and cancels pending leases.
- Loopback-only inspection/write endpoints respect existing same-origin checks. Model output is never treated as executable instructions. The local API is not a multi-user authentication boundary.
- Existing core video, account connections, mic, ElevenLabs and personal store preserved. No background audio recording. While the computer is off/asleep or app is stopped, no study executes.

## Tests
- Six new SQLite tests: explicit scope, source filtering, dedup/persistence, changed evidence and stale lease, pause/stop, crash/retry limit, 24-hour budget, validation.
- Full Python regression: 236 tests passed before final packaging; Swift intent smoke passed.
- Manual actual Qwen smoke: PYTHONPATH=. python3 tests/study_live_smoke.py. Separate temporary database and random loopback port, no user records changed. Confirmed no claim while dialogue simulated active, actual model draft after release, persisted source references and source status after DB reopen.
- Synthetic fixture only: 1000 ad impressions / 20 clicks / purchase unknown. First model output overclaimed a hypothesis was false; strengthened prompt to distinguish lack of evidence from refutation. Rerun correctly declined conversion judgment and proposed purchase logs. This is a single validated example, not proof of general reasoning accuracy.
- Installed app and real API status checked separately. Real mic/TTS, GPU contention, actual interruption latency, autonomous long-term research quality still unverified.

## Next
ACTION CORE: before any publishing/spending, implement read-only data collection and scoped explicit authorization; draft/review/approval and result auditing. Keep model-independent export/restore and device migration on roadmap.
