# Conversational Review and AI activity trial

13 October 2026. Historical source-free prototype checkpoint, based on `b079295`. The user approved this interaction; connected production behaviour and current validation are recorded in [HOW_IT_WORKS](HOW_IT_WORKS.md) and [STATUS](../STATUS.md). The sections below describe the original scripted comparison and its limits.

## Try it

Run `scripts/demo-review-conversation.sh`. It builds a signed DEBUG candidate in a unique temporary folder and opens only `--preview-review-conversation`. An existing candidate can be selected with `MISSIONCONTROL_TRIAL_APP`.

The native window has a **Current idea / Trial** switch. Current idea is a simplified, fictional reference for the basic reminder form, not a reproduction of every installed feature. Trial shows one project email as a conversational plan. The installed application remains the actual old-version comparison.

1. Click the heartbeat icon in the toolbar, then **Explore suggested actions**.
2. Read the proposed project tasks and Calendar entries. Clear actions you do not want, or say **project tasks only**, **calendar only**, or **leave November out**. A variation revises the plan and needs a subsequent approval.
3. Say **yes**. While the example heartbeat is running, the request queues without interrupting it.
4. Close Review. Open Today, Projects or general Chat. The queued request and its Review transcript remain with the suggestion.
5. Inspect the centred pill. Its circular chat icon opens general Chat; its status text opens activity. After the heartbeat, the queued request starts and its progress replaces heartbeat progress.
6. Inspect Projects and Calendar after completion.

For a failure example, reset the example, enable **Next request: unconfirmed Calendar save** in the toolbar’s demo controls, and approve the plan. The pill retains a warning, activity names the affected action, and completed actions remain visible. **Check example Calendar save** resolves the same simulated operation by readback, without creating a duplicate. Stop pauses the queue; **Continue queue** resumes only never-started requests. Controls can pause automatic progression, finish a heartbeat immediately, change the example account and switch appearance.

## What the plan illustrates

The example is synthetic and paraphrased; it contains no imported email body, sender, account credentials, real project identity or private source cache. It mirrors a compound engineering-project schedule:

| Milestone | Project task | Calendar proposal |
| --- | --- | --- |
| Michaelmas presentation window | Undated preparation task | Two provisional daily windows, 26–27 November 2026, 08:30–17:00 |
| Technical milestone report | Due 21 January 2027, with 16:00 recorded in notes | Explicit 16:00–16:15 deadline marker |
| Final report | Due 31 May 2027, with 16:00 recorded in notes | Explicit 16:00–16:15 deadline marker |
| Final presentation | Date-only 4 June 2027 milestone | All-day date marker; individual time unallocated |

The hazard assessment is explained in text. This example supplies no due date and does not create another hazard-assessment task automatically. Provisional windows are disclosed; deadline marker duration is a proposed convention, not a claimed source meeting duration.

## Implemented in the trial

- Native toolbar with a centred pill, circular chat button, animated progress ring, queued count and persistent outcome indicator.
- Local Review conversation with selected concrete actions, plain-language scripted variations and explicit approval.
- One app-owned in-memory simulation clock, independent of the Review sheet’s lifetime. Heartbeat runs first; accepted Review requests wait and execute serially.
- Immutable accepted action snapshots, stable operation identities, coalesced identical pending plans and per-action simulated receipts.
- Success, partial completion, Stop and account-change rejection. Unconfirmed saves cannot be resubmitted until checked.
- Separate example project/Calendar result views and a general-chat view without Review turns.
- Source-free launch before personal storage restoration, source/helper startup or inference. Production toolbar, scheduling, approval and conversation paths are unchanged.

## Explicit limits

This is a **scripted interaction prototype**, not a reasoning-quality evaluation. It performs no ChatGPT inference or real Apple/project write. Jobs and transcripts live only in memory and reset on relaunch. Progress belongs to simulated stages, not measured provider timing. The baseline form is illustrative. The demo does not establish production persistence, Undo, native execution, recurrence, source withdrawal, race safety or provider reliability.

The production system already asks for paired Calendar/project milestone suggestions, but current evidence still shows model omissions. A conversational display alone does not fix that reasoning gap.

## Original production integration plan (now historical)

Keep one owning integration chat. Add an account-owned Review conversation and durable job record rather than route hidden turns through `AssistantService.send`, which currently targets the primary feed. Reuse `PAConversationEngine` and typed tools through a Review-specific service.

Capture the exact displayed `preparedApprovalSnapshot` for each action, human reply/turn identity, registration/storage/model/Focus/source choices, destination and canonical pending/complete receipts. New advice retains current evidence checks. Approval of displayed creations follows current Review policy: concrete payload, destination/account and uncertain/duplicate receipts plus verified readback, without broad memory/source revision gates. Edits/removals retain exact current target/occurrence checks. A project description change alone cannot block an accepted creation.

Scheduling belongs in one app-owned coordinator. Persist enqueueing immediately without invoking foreground typing hooks. Start once the heartbeat and all child workers unwind; closing a page does not cancel an accepted job. Foreground typing/Stop, ownership changes and sleep remain authoritative. Never-started authorised jobs may survive reopening; attempted or uncertain operations must not automatically replay.

Pill outcomes must derive from verified structured receipts and unresolved tool failures, not fluent assistant prose or `error == nil`. Keep partial successes and expose the exact remaining action. Preserve operation identity across retries, isolated Review history and main-chat drafts/Focus.

## Acceptance before merging a connected version

- Held heartbeat → submitted yes → one durable waiting job, zero inference/write calls → exactly one start after parent and children finish.
- Leave Review or open Chat: job and isolated transcript survive. Reopen before starting: waiting work survives. Reopen after an attempt: no automatic replay.
- Multiple requests run serially. Needs-answer, provider failure, Stop or ownership change pauses subsequent work.
- Change account/model/storage/source choices: no late or retargeted save. Change an unrelated memory or project description after approval: creation stays valid. Change captured destination/target: reject appropriately.
- First action succeeds, second fails: retain the first receipt; show partial completion and exact failed-action details. A final success-sounding response cannot hide a failed tool.
- Native save succeeds but receipt/readback fails: show uncertain, inspect the original operation, refuse duplicate creation.
- Compare actual model proposals against the complete compound schedule, including omissions, provisional presentation scope and absent hazard deadline.
- Retain saved toolbar identities/arrangement, compact window fit, palette overrides, layouts and keyboard/focus behaviour. Native and project Undo policies remain explicit.

Evidence for this prototype is recorded in STATUS and VALIDATION. Screenshots and build logs stay outside Git.
