# AI job continuity audit — 17 October 2026

The user asked for ordinary app edits to leave AI work running unless the work becomes unavailable, conflicting or impossible. The earlier Review Dismiss repair was one instance of a wider problem: several consumers treated mutable future defaults or whole-store revisions as ownership of an already accepted job.

Implemented and installed code: `3bef5e9`. This changes the current experience; it adds no AI agent, screen, automatic retry or source permission. Existing failed requests and operation identities are preserved.

## Repaired cases

| Change while work is running | Result after this repair |
| --- | --- |
| Selected model, assistant name, writing instructions or relevance Focus | The foreground request keeps its captured model/instructions/Focus through subsequent tool rounds. Intent and organisation checks use that same model. New requests use the new defaults. Accepted Review/feedback jobs retain their submitted model. |
| Brief writing prompt or general writing preferences | The current brief/Review uses its captured instructions. Editing the brief prompt applies to subsequent work. |
| Heartbeat interval | Updates future scheduling without cancelling the owned cycle. Actual disabling, Stop, sleep, provider limits and run ownership remain separate. |
| Opening/restoring a draft, typing, pasting or removing an attachment | Preserves active work. Actual edits defer new automatic starts through the quiet window. Restoration itself is not typing or Stop. |
| General Send while an assistant/Review conversation is active | Uses the existing serial queue without interrupting that conversation. While a background provider call is active, the existing Send readiness contract retains the draft until the call finishes. An accepted idle Send deliberately hands over foreground ownership. |
| Allow memory learning | Does not revoke read-only memory use in chat, email, Review or a brief. A separate memory-use generation retains actual read-permission withdrawal checks. |
| Unrelated memory saves, edits or Forget during conversation learning | Validates the 20 actually selected facts, up to eight supplied historical correction records and suppression for the captured conversation batch. Merges supported output into current state under the existing storage CAS. |
| Disable learning questions | Saves supported learned facts while withholding a newly disabled question. It does not discard the whole result. |
| Dismiss/Undo another memory-maintenance proposal, or change another account's automatic-maintenance choice | Preserves the current proposal state and completes the independent pass. Exact supplied facts and current human choices remain checked. |
| Change learning permission for another native source kind | Does not cancel the active source learner. Its own account/kind permission generation remains guarded. |
| Change unrelated Calendar/list choices during email feedback | Feedback validates its exact Mail account, message/content, current access, storage and issued memory identity. It no longer depends on the whole source-settings hash. |
| Save an independent native/project edit | Does not explicitly cancel heartbeat/feedback. Native writing remains a new-job admission gate, while running analysis checks the exact supplied evidence. A changed supplied occurrence still rejects stale output. |
| Change source choices during a heartbeat child | The parent no longer treats one global source hash as ownership of every stage. Child permission/evidence failures retain their failure receipts while independent supported stages can finish. |
| Change WhatsApp learning or another consumer/account's options | Conversation, brief and Review have purpose/account-scoped read generations. No-op saves do nothing. Disconnect/revocation/relink changes a separate identity generation, including a return to the same identity. |
| Change an unused weather/WhatsApp source | Foreground dependencies attach to data actually supplied, including later tool reads and attention provenance. A connector merely being enabled is insufficient. Weatherless brief preparation does not depend on weather permissions. |
| Save an unrelated project task/note before removing a read relationship | Compares the exact captured relationship and owner, then saves against current synchronous store CAS. New approval snapshots retain exact relationships; legacy snapshots preserve their conservative compatibility check. |

## Boundaries retained

Admission checks determine when work can start. They are distinct from the predicates that can invalidate an already owned request. Explicit Stop, account/storage changes, withdrawn source permissions, actual provider unavailability, exact native/project conflicts, correction/Forget lineage, uncertain-operation receipts and verified readback remain checked. Returning from a denied permission to the same apparent settings does not revive an old permission owner.

The audit also inspected non-AI Calendar drag and Projects view/widget mounting guards. Their mounted-target/current-view contracts remain; this repair does not change pointer-gesture ownership or navigate the user to a widget they have left. New source access, repeating-item scope, uncertain saves and actual missing targets still require their existing preparation/recovery rather than replaying a failed operation.

## Validation

All 18 affected source-free suites pass on the combined code: 699 actual foreground-service contracts, 404 learning checks, 691 maintenance/organisation assertions across 47 runs, 165 scheduler contracts, 133 Review queue checks and 63 actual relationship-tool/store checks, plus the related component suites. Original relationship code reproduces its unrelated-save rejection before the fix. The inventory now includes the relationship suite.

Signed production consumers pass 674/674: 495 advice/context assertions, 145 scheduler/brief assertions and 34 removal contracts. These include held inference, settings/draft/native-writing changes, exact-source negative cases, completed receipts and reopen checks. Disposable native fixtures pass 17/17 with verified cleanup. No subscription inference or personal native operations were used for QA. Full signed Debug build and strict signature pass. Independent review caught and corrected a reconnect permission-generation gap and an overly broad attention-read dependency before release; an intermediate protocol-witness compile error was repaired before final validation.

Data-preserving installation/readback and private evidence locations are recorded in STATUS/VALIDATION. Sustained real provider/source traffic, OS sleep/wake and broad model quality are separate from these bounded concurrency contracts.
