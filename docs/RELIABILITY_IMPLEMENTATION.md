# Reliability and architecture implementation

Approved by the user on 11 October 2026. Baseline: `b092562`, after the Review/memory-feedback work completed. The owning integration chat implements the full seven-stage plan and verifies completion against this checklist. Phone support is outside this work.

## Completion checklist

| Stage | Required deliverable | Evidence needed | Current state |
| --- | --- | --- | --- |
| 1. Baseline | One isolated source-free regression command; distinct service/native/model tiers | Baseline results, failure inventory and per-run outputs | Final source-free inventory passes 59/59; distinct signed candidate tiers implemented |
| 2. Correctness | Short meaningful query terms; unavailable Reminders distinct from empty; isolated action persistence | Reproduced regressions, final failure/reopen checks | Regression, persistence and source-free candidate checks pass; exact heartbeat child completion guards added |
| 3. Structure | Explicit repositories, source readers, conversation engine, background coordinator and action boundary | Fictional sources/clock/storage exercise runtime without dashboard | Implemented; actual assistant 50, learning 22 and heartbeat 124 contracts pass; signed build and app tiers pass |
| 4. Fair learning | Eligible lanes receive shared allowance fairly, retaining pauses and foreground priority | Multi-day starvation/cooldown/account/interruption scenarios | 159 persisted budget checks and 22 actual-service checks pass; observed use pending |
| 5. Performance | Measured conversation saving, recall and navigation; bounded improvements; migration only if justified | Before/after fictional workloads, preservation/reopen checks | Measured cached memory, changed chunks and navigation; UI acceptance pending |
| 6. Quality and docs | Fixed realistic memory scenarios and current architecture/behaviour/validation/roadmap | Separate deterministic/model evidence; documentation consistency | Deterministic quality 64/64; final configured-model tier 5/5 (61 assertions/nine fictional requests); docs reconciled; broad semantics remain limited |
| 7. Integration | Signed candidate, disposable native acceptance, normal data preservation and sustained observation | Combined checks, signature/install/readback, relaunch and several days of observed use | All candidate tiers and backed-up installation/readback/relaunch/preservation pass; sustained and physical acceptance remain |

## Ownership and contracts

The main checkout owns shared storage, application interfaces, scheduling, integration and shared documentation. Isolated workers from the same baseline own test scripts, memory selection/scenarios, and native read resolution. Workers do not install candidates or touch personal sources. The integration owner reviews and combines their commits.

All work preserves stable IDs, account/registration boundaries, source consent, evidence/history, drafts/layouts, tombstones, pending native receipts and supported Undo. Foreground work remains explicit and stoppable. Collection remains no-AI. Failed or interrupted foreground writes are never automatically replayed. Existing learning allowances/cooldowns and failed-claim pauses remain.

Every implementation checkpoint records changed behaviour, focused checks, integration checks and remaining acceptance. Synthetic timelines cannot substitute for physical sleep/wake or several days of real operation. No checkpoint claims the full goal complete while a required row remains unverified.

## Current integration evidence — 12 October

Final source-free inventory: `/private/tmp/missioncontrol-check-0grobw_d/results.json` (59/59). Signed app-memory: `/private/tmp/missioncontrol-check-6ilz4px7/results.json` (137/137 consumer, 62/62 scheduler/storage and 11/11 removal contracts; zero model/native changes). Optional performance: `/private/tmp/missioncontrol-check-3hbi2orz/results.json`. Prior model tier: `/private/tmp/missioncontrol-check-c3vm8ntq/results.json` (4/5; valid empty commitment extraction was a quality failure, not success). STATUS and VALIDATION retain intermediate failures and distinguish candidate results from the still-required installation/sustained acceptance.

Final native: `/private/tmp/missioncontrol-check-sg4lvwcx/results.json` (24/24, cleanup verified, zero AI). Final configured model: `/private/tmp/missioncontrol-check-51tuu4bi/results.json` (5/5, 61 assertions/nine fictional requests). Installed at code checkpoint a63b2da; [live acceptance](LIVE_ACCEPTANCE.md) remains open.
