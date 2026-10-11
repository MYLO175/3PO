# Reliability and architecture implementation

Approved by the user on 11 October 2026. Baseline: `b092562`, after the Review/memory-feedback work completed. The owning integration chat implements the full seven-stage plan and verifies completion against this checklist. Phone support is outside this work.

## Completion checklist

| Stage | Required deliverable | Evidence needed | Current state |
| --- | --- | --- | --- |
| 1. Baseline | One isolated source-free regression command; distinct service/native/model tiers | Baseline results, failure inventory and per-run outputs | In progress |
| 2. Correctness | Short meaningful query terms; unavailable Reminders distinct from empty; isolated action persistence | Reproduced regressions, final failure/reopen checks | In progress |
| 3. Structure | Explicit repositories, source readers, conversation engine, background coordinator and action boundary | Fictional sources/clock/storage exercise runtime without dashboard | Pending |
| 4. Fair learning | Eligible lanes receive shared allowance fairly, retaining pauses and foreground priority | Multi-day starvation/cooldown/account/interruption scenarios | Pending |
| 5. Performance | Measured conversation saving, recall and navigation; bounded improvements; migration only if justified | Before/after fictional workloads, preservation/reopen checks | Pending |
| 6. Quality and docs | Fixed realistic memory scenarios and current architecture/behaviour/validation/roadmap | Separate deterministic/model evidence; documentation consistency | Pending |
| 7. Integration | Signed candidate, disposable native acceptance, normal data preservation and sustained observation | Combined checks, signature/install/readback, relaunch and several days of observed use | Pending |

## Ownership and contracts

The main checkout owns shared storage, application interfaces, scheduling, integration and shared documentation. Isolated workers from the same baseline own test scripts, memory selection/scenarios, and native read resolution. Workers do not install candidates or touch personal sources. The integration owner reviews and combines their commits.

All work preserves stable IDs, account/registration boundaries, source consent, evidence/history, drafts/layouts, tombstones, pending native receipts and supported Undo. Foreground work remains explicit and stoppable. Collection remains no-AI. Failed or interrupted foreground writes are never automatically replayed. Existing learning allowances/cooldowns and failed-claim pauses remain.

Every implementation checkpoint records changed behaviour, focused checks, integration checks and remaining acceptance. Synthetic timelines cannot substitute for physical sleep/wake or several days of real operation. No checkpoint claims the full goal complete while a required row remains unverified.
