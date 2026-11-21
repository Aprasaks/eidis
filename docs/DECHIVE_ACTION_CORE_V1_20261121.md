# DECHIVE ACTION CORE 1.0
2026-11-21

## Scope
Explicit, allowlisted report jobs: project report, YouTube report, and project + YouTube report. A local persistent queue records request, state, data-source observations, summary and readable Markdown report. It is not yet general-purpose computer use.

## Execution
- Rules recognize affirmative spoken requests before the model/tool router. No generated shell, arbitrary URLs, unrestricted file access, external writes, or automatic study-to-action promotion.
- One background worker at a time; 8 pending jobs maximum. Local projects and task counts are read from a separate read-only SQLite transaction. YouTube uses existing authorized read-only summary adapter (including its existing five-minute cache; observation timestamp is preserved).
- SQLite stores results, source scope and observation time. Display counts are from actual records. Missing YouTube analytics yields partial completion, not invented zero. Project status remains untouched. The report lists at most 40 project details and 12 blocked task details; totals are uncapped.
- Cancellation prevents new stages and discards late results. A provider call already in progress may continue until return/timeout; no guarantee of instant network cancellation. On restart, a lost running job is marked failed, while queued work can be resumed. Completed reports remain readable.
- Spoken report output is bounded while the full stored report is displayed in dialogue.
- Same-origin loopback endpoints: GET /api/action, GET /api/action/job?id=N, POST /api/action/submit {workflow}, POST /api/action/cancel {id}. This is not a new auth boundary against software running on the same Mac.

## Example Korean intents
- 자비스, 프로젝트 보고서 만들어줘
- 자비스, 유튜브 현황 보고서 작성해줘
- 자비스, 프로젝트와 유튜브 보고서 만들어줘
- 자비스, 업무 현황 알려줘
- 자비스, 업무 보고서 1번 보여줘
- 자비스, 업무 1번 중단해

## Verification
243 Python tests passed (7 new action tests). Mac Swift compile and explicit intent smoke passed. YouTube tested with synthetic provider responses, including failure, missing analytics and credential field exclusion; real account reads only on explicit request. Actual local report verification after installation recorded separately. Existing database backup before migration; core video preserved. Live voice timing and general GUI actions remain unverified.

## Next
Add scoped read-only research tools, durable multi-step execution and then a restricted browser workspace with observation, action and result verification. External publishing and account-changing actions require separate explicit approval; no autonomous spending, posting or deletion in this release.

## Installed verification
Mac installed and relaunched; code signature verified, packaged/installed executable hashes matched, core video hash unchanged. Real queue job #1 completed using local SQLite: 2 projects, 25 tasks, 14 done, 11 todo, 11 open review alerts, observation 2026-11-21T03:49:44+00:00. Existing table counts unchanged and SQLite quick_check returned ok. No real YouTube call made in this test. Reports are persisted in the local job ledger.
