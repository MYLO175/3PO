# Mission Control code audit

## Repair checkpoint — 16 October

The findings below describe the audited pre-repair checkout. The repair branch addresses all sixteen numbered defects; follow-on acceptance and installation evidence is indexed in [VALIDATION](../VALIDATION.md) and [STATUS](../STATUS.md). The larger architecture proposals below remain follow-up work.

| Findings | Repair |
| --- | --- |
| 1, 8, 10, 11 | Displayed Reminder baseline and full Undo snapshots; cancellable/deadlined reads; durable proof separating pre-save refusal from uncertain saves, including direct creation forms. |
| 2, 5, 13, 14 | Application/repository writer leases, exact loaded-byte checks, opaque-field preservation, retained operation identities and selected-subtree restore. |
| 3 | Reusable account/Focus/revision-scoped Projects index replaces repeated ancestor scans. |
| 4, 12 | Durable WhatsApp learning admission generations; exact relevant native learning checks. |
| 6, 15, 16 | Selected-context/history dependencies, uncapped foreground request counts, cached ordinary transcript projection with current delivery support checks. |
| 7, 9 | Per-account Mail discovery failures and no publication for WhatsApp status-only updates. |

The active Projects limit excludes retained tombstones. Full-record Projects serialization and delivery-history support scans remain scaling limits; no new database schema, retrieval model, permissions or inference provider is introduced. Cooperating versions honor storage locks; an older binary launched afterward cannot be made to cooperate, so release checks also exclude old running copies. Benchmarks are fictional component measurements, not end-to-end UI or model-quality guarantees.


16 October 2026. Reviewed main commit `63e7a4c6d65dd9f59bf88ba083d3026204cff6ac`.

The most valuable work is to strengthen three foundations: exact native-operation ownership, storage ownership, and bounded UI projections. The app already has useful service boundaries, durable receipts, source-aware memory, fictional runtime fixtures and incremental conversation storage. The main weakness is inconsistent application of those contracts: newer paths have strong checks while older paths bypass them; some jobs validate unrelated state; some views rebuild substantially more than they display.

This audit identifies concrete defects and measured bottlenecks below, followed by architectural improvements. It makes no product-code changes. Findings marked **reproduced** use fictional data against production functions or services. **Source verified** means the control flow was inspected, without performing the corresponding personal/native operation. P1 means address first because of potential data loss, an incorrect write, or a substantial UI stall; P2 means a significant bounded defect or scaling problem. These are repair priorities, not claims that every trigger has occurred in normal use.

## Recommended repair order

| Order | Work | Why it comes first |
|---|---|---|
| 1 | Bind Reminder completion and Undo to exact displayed and saved versions | Prevent completing a changed occurrence or undoing later work |
| 2 | Enforce a single personal-storage writer and durable operation identities | Prevent lost edits and lost uncertain-operation barriers |
| 3 | Index and cache the Projects page projection | Remove a measured seconds-long main-thread calculation |
| 4 | Repair source collection and learning boundaries | Isolate failing accounts, make Stop responsive, baseline newly permitted history |
| 5 | Narrow AI dependencies and distinguish pre-save failure from uncertainty | Preserve valid conversations and make failures recoverable |
| 6 | Reduce repeated snapshot, transcript and inference work | Improve latency and resource use against measured baselines |

## Findings

### 1 P1 The Reminder checkbox does not validate the displayed occurrence

**Source verified.** [DashboardModel.swift](/Users/mylomichael/Documents/Developer/Mission%20Control/MissionControl/DashboardModel.swift:671) receives a complete displayed `TaskItem` but forwards only its ID to completion. [EventKitService.swift](/Users/mylomichael/Documents/Developer/Mission%20Control/MissionControl/EventKitService.swift:83) accepts an optional expected baseline; when absent it adopts the current Apple item.

If a recurring reminder has advanced in Apple Reminders while 3PO still shows its earlier occurrence, clicking the old checkbox can complete the new occurrence. Changes to title, list and due date before the click are similarly accepted. The full recheck immediately before saving protects changes during execution, but cannot recover the discarded displayed baseline.

**Repair:** resolve completion against the captured `TaskItem` and retain its exact item/occurrence baseline through permission checks and save. Pass the existing ownership validity callback too. **Acceptance:** unchanged displayed reminders complete normally; the same ID with changed due date, list, title or advanced recurrence produces zero writes and a refresh.

### 2 P1 A stale second writer can erase projects and pending operation receipts

**Reproduced; conditional on competing loaded writers.** [LocalRecordRepository.swift](/Users/mylomichael/Documents/Developer/Mission%20Control/MissionControl/LocalRecordRepository.swift:35) replaces bytes without a persisted expected revision. [ActionReceiptStore.swift](/Users/mylomichael/Documents/Developer/Mission%20Control/MissionControl/ActionReceiptStore.swift:23) loads a whole ledger once and later rewrites that snapshot. [LifeWorkspaceStore.swift](/Users/mylomichael/Documents/Developer/Mission%20Control/MissionControl/LifeWorkspaceStore.swift:232) follows the same pattern.

Two loaded project stores were given separate creations. After A saved and B saved, reopening contained only B's creation. Two receipt stores likewise lost A's pending claim when B began its operation. Losing a pending claim is more serious than losing a display update: it removes part of the protection against repeating an uncertain native save.

Normal application construction has one owning model; this is not evidence of a normal single-process asynchronous race. It is a competing-copy vulnerability. The recent stale-app-copy incident recorded in STATUS makes that trigger practically relevant.

**Repair:** acquire an exclusive process lease before opening personal storage, then introduce transactionally checked persisted versions or independently keyed append-only receipts. A read-before-write comparison alone is insufficient across processes. **Acceptance:** two disk-backed writers cannot silently overwrite each other; pending claims survive every stale save attempt.

### 3 P1 Projects Focus filtering is quadratic and can stall the UI for seconds

**Measured.** [LifeProjectWidget.swift](/Users/mylomichael/Documents/Developer/Mission%20Control/MissionControl/LifeProjectWidget.swift:46) computes inherited areas for every item, then walks matching paths again. Each call to [LifeItemQuery.path](/Users/mylomichael/Documents/Developer/Mission%20Control/MissionControl/LifeWorkspaceQuery.swift:33) rebuilds a dictionary of the complete item collection. The widget's `current`, `children`, `shows` and other computed properties can request this projection repeatedly during one update.

One exact projection, excluding SwiftUI rendering and repeat calls:

| Fictional items | Current Debug mode | Optimized build |
|---:|---:|---:|
| 100 | 12.72 ms | 5.08 ms |
| 1,000 | 1.153 s | 382.48 ms |
| 5,000 | 31.652 s | 10.003 s |

The fixture contains one root with matching task children and inherited Studies focus. It exercises the real store/query functions and the widget's projection. Optimization helps, but leaves the algorithmic problem. These are indicative isolated-workload timings, not measured live-window latency.

**Repair:** construct `byID`, children and inherited-area indexes once per workspace revision, and prepare a page projection keyed by registration, topic, Focus, folder and relevant presentation inputs. Pass that snapshot through the view. **Acceptance:** unchanged render/drag updates reuse the projection; growth toward 5,000 items is approximately linear; account and Focus changes invalidate correctly.

### 4 P2 Adding a WhatsApp chat can automatically analyse its old cached messages

**Reproduced through the actual learning service.** [SourceContextLearningService.swift](/Users/mylomichael/Documents/Developer/Mission%20Control/MissionControl/SourceContextLearningService.swift:25) keys progress by registration and linked identity. Its inherited-permission baseline at line 57 only runs when that entire scope is new.

Chat A was correctly baselined without inference. Adding B to the same inherited Review-learning scope then caused an automatic fake-inference call for B's six-hour-old message. The selected-chat set changed, but the existing scope prevented a new baseline. This violates the current requirement that newly inherited access baseline existing content rather than silently backfill it.

**Repair:** persist the admitted chat set or permission epoch, and baseline newly admitted content on scope expansion or re-enablement. Keep explicit Review once as the bounded historical assessment route. **Acceptance:** initial opt-in, added chats, withdrawal/re-enablement and reopening preserve the baseline; genuinely new later messages remain eligible.

### 5 P2 Ordinary Projects edits discard unknown additive fields

**Reproduced.** [LifeWorkspaceStore.swift](/Users/mylomichael/Documents/Developer/Mission%20Control/MissionControl/LifeWorkspaceStore.swift:36) decodes a typed state and subsequently re-encodes it wholesale at line 236. Synthesised Codable discards unrecognised keys even when the schema remains version 1.

Unknown optional fields inserted at envelope and item levels disappeared after an ordinary note edit. An older app reopened against a newer additive record can therefore strip information it does not understand. Conversation storage already preserves opaque fields, so compatibility guarantees differ between stores.

**Repair:** preserve opaque fields by canonical identity, or reject unsupported schemas before enabling writes. **Acceptance:** future optional fields survive editing, structural changes and Undo at nested levels; unsupported data leaves the original bytes intact.

### 6 P2 Every assistant reply depends on unrelated source memories

**Source verified.** The assistant selects relevant context, but [AssistantService.swift](/Users/mylomichael/Documents/Developer/Mission%20Control/MissionControl/AssistantService.swift:528) separately captures every usable source-memory ID. At line 611 it attaches that union to each reply. [ConversationRules.sourceMemoryHistory](/Users/mylomichael/Documents/Developer/Mission%20Control/MissionControl/Conversations.swift:192) excludes a reply from future model history if any attached ID becomes unavailable.

A coursework answer can therefore disappear from usable history because an unrelated WhatsApp fact loses evidence. The saved transcript remains intact, but follow-ups such as “yes, do that” can lose their assistant-side context. The same broad set participates in active-request validation, so unrelated source availability can also interrupt an answer.

**Repair:** record dependencies from selected input memories, notebook fact IDs and actual successful memory-tool reads. Keep mutation-issued IDs separate. **Acceptance:** revoking unrelated fact B preserves a reply using A; revoking A still withdraws dependent advice/history.

### 7 P2 One broken Mail account blocks healthy account collection

**Helper behavior reproduced; dashboard control flow verified.** [MailReader.js](/Users/mylomichael/Documents/Developer/Mission%20Control/MissionControl/Mail/MailReader.js:266) returns healthy accounts alongside per-account discovery errors. [DashboardModel.refreshMail](/Users/mylomichael/Documents/Developer/Mission%20Control/MissionControl/DashboardModel.swift:614) throws on any discovery error before processing those accounts.

A persistently broken Inbox therefore prevents arrivals and reconciliation for healthy accounts too. Later per-account backoff cannot help because this happens before the per-account loop.

**Repair:** collect healthy accounts while retaining failed-account caches, identities and cursors; report discovery failure per account. Simply deleting the throw would be insufficient because the following enabled-account filtering could otherwise remove failed-account cached coverage. **Acceptance:** healthy accounts advance while unavailable accounts retain their prior data and explicit incomplete coverage.

### 8 P2 Stop cannot interrupt a pending Reminders fetch

**Reproduced.** [NativeSourceRead.fetchSnapshot](/Users/mylomichael/Documents/Developer/Mission%20Control/MissionControl/NativeSourceRead.swift:35) checks cancellation around a continuation but has no cancellation handler or deadline. [EventKitService.swift](/Users/mylomichael/Documents/Developer/Mission%20Control/MissionControl/EventKitService.swift:18) discards the native fetch token.

A fictional held callback left the actual adapter unfinished 200 ms after cancellation. It threw `CancellationError` only after the callback was manually released. A missing callback can leave foreground work waiting and the background collector loading indefinitely.

**Repair:** retain the native token and use a cancellation/deadline controller that resumes exactly once. The installed EventKit SDK provides `cancelFetchRequest`; cancelling the native request suppresses its callback, so the controller must also finish the continuation. **Acceptance:** cancellation, timeout, completion and simultaneous cancellation/completion all terminate exactly once without accepting late output.

### 9 P2 Status-only WhatsApp updates rewrite and publish the entire cache

**Reproduced using the actual reader handlers and reconciliation code.** [reader.mjs](/Users/mylomichael/Documents/Developer/Mission%20Control/WhatsAppBridge/reader.mjs:75) unconditionally publishes after `messages.update`, even when reconciliation ignores an update that only changes receipt status. Publication at line 29 serializes/encrypts/writes complete snapshots and emits all messages. [WhatsAppService.swift](/Users/mylomichael/Documents/Developer/Mission%20Control/MissionControl/WhatsAppService.swift:167) decodes/reassigns that array and invalidates fingerprint caches.

One unchanged status update over 2,000 fictional 5 KB messages caused two encrypted writes totalling **10,193,869 bytes**, plus **10,181,081 bytes** of stdout. This unnecessary amplification grows with retained history and update frequency.

**Repair:** return change flags or revisions, skip unchanged publications, and coalesce changed batches. Separate journal durability from UI publication while preserving journal-before-message crash safety. **Acceptance:** unchanged status updates perform zero message-snapshot writes/publications; content edits, deletions and recovery still propagate correctly.

### 10 P2 Completion Undo can reverse later external work

**Source verified.** [EventKitService.CompletionRecord](/Users/mylomichael/Documents/Developer/Mission%20Control/MissionControl/EventKitService.swift:11) stores IDs and due dates, rather than complete post-save baselines. [undo](/Users/mylomichael/Documents/Developer/Mission%20Control/MissionControl/EventKitService.swift:127) accepts a nonrecurring reminder whenever it is completed. Recurring Undo checks dates and list equality but omits full title/notes/recurrence/revision/completion-time identity.

An external edit, or an external undo followed by a new completion, can leave the old token able to reverse later work. A recurring Undo may also delete an externally edited detached completion.

**Repair:** capture exact post-save baselines for original and detached records; reset/refetch and compare them before Undo. **Acceptance:** stale tokens after edits, recurrence changes and independent recompletion reject without writes; ordinary supported Undo remains available.

### 11 P2 Known pre-save failures are classified as uncertain native saves

**Source verified.** [AssistantActions.performTool](/Users/mylomichael/Documents/Developer/Mission%20Control/MissionControl/AssistantActions.swift:51) persists a pending claim, invokes the writer, and wraps every writer error as `PANativeActionUncertainty`.

The writer can reject missing defaults, stale baselines, invalid options or cancellation before attempting any save. These known failures still retain an uncertain claim and can halt remaining work as though Apple may already have saved. This is safe against duplicate writes but unnecessarily strands recoverable operations.

**Repair:** report the mutation phase explicitly. Resolve proven pre-save failures durably as unattempted/failed; retain uncertainty for attempted saves, failed readback and failed receipt persistence. **Acceptance:** injected pre-save failures leave no false uncertainty; attempted-save/readback failures continue to block replay.

### 12 P2 Unrelated EventKit changes pause Mail learning until manual recovery

**Reproduced through actual production services.** [NativeSourceLearningService.swift](/Users/mylomichael/Documents/Developer/Mission%20Control/MissionControl/NativeSourceLearningService.swift:95) captures global `sourceRevision` and checks it at line 103 even for Mail learning. Exact supplied items are already compared separately. [DashboardModel.swift](/Users/mylomichael/Documents/Developer/Mission%20Control/MissionControl/DashboardModel.swift:414) increments that global value on EventKit notifications.

Changing only the global revision during fake inference rejected an unchanged Mail batch. The earlier persisted `paused=true` claim remained, and the next automatic check made no call. An unrelated Calendar sync can thus waste inference and require explicit Review once.

**Repair:** validate exact input versions plus purpose-specific permission/ownership changes. **Acceptance:** unchanged Mail work survives unrelated EventKit notifications; changed Mail evidence, account withdrawal and permission changes still reject.

### 13 P2 Project operation identities expire after 2,000 later receipts

**Reproduced.** [LifeWorkspaceStore.addReceipt](/Users/mylomichael/Documents/Developer/Mission%20Control/MissionControl/LifeWorkspaceStore.swift:225) unconditionally removes the oldest receipt at 2,000. Project tools use these identities to recognize completed operations.

After seeding 2,000 receipts and adding another, the first identity disappeared. Reusing that exact operation ID successfully created another item after the original was renamed. Consumer job phases reduce opportunities to reach this state, but the store no longer guarantees durable idempotency. Title checks do not replace operation identity.

**Repair:** preserve compact operation-key tombstones independently of prunable result prose, including all identities referenced by recoverable jobs. **Acceptance:** old exact operations remain recognizable after the retention boundary, rename, move and reopen.

### 14 P2 Restoring one deleted task also restores unrequested siblings

**Reproduced.** [LifeWorkspaceStore.restore](/Users/mylomichael/Documents/Developer/Mission%20Control/MissionControl/LifeWorkspaceStore.swift:116) expands the selected item to every deleted record sharing its original `deletedRoot`. The AI tool accepts an individually issued deleted descendant, unlike the native Recently deleted UI, which offers deletion roots.

Deleting a folder containing A and B, then restoring A's ID, restored all three records. The tool describes A as restored while also changing its parent and B.

**Repair:** restore the selected subtree and rehome it if necessary, or require the deletion root and authorize the full affected set. **Acceptance:** child restoration leaves siblings unchanged unless the human approved the whole branch; report the actual affected items.

### 15 P2 Foreground queued work retains retired count limits

**Source verified.** [PARequestQueue.swift](/Users/mylomichael/Documents/Developer/Mission%20Control/MissionControl/PARequestQueue.swift:35) rejects stored queues over 100 entries and refuses the 21st outstanding request for one registration or the 101st globally. This contradicts the current explicit no-fixed-count-cap policy.

**Repair:** remove outstanding-request count caps while retaining per-request size/image bounds, Stop, loop detection and recovery semantics. Treat pruning completed presentation history separately from operation identities. **Acceptance:** 21+ waiting requests add/reopen correctly, with interrupted and needs-answer behavior retained.

### 16 P2 Chat rebuilds complete history for every streamed update

**Measured.** [AssistantView.swift](/Users/mylomichael/Documents/Developer/Mission%20Control/MissionControl/AssistantView.swift:76) filters/sorts the thread, then at line 211 creates transcript rows and separators for every turn before selecting the visible suffix. Pagination limits displayed rows, not projection work. New partial content invalidates the panel; line 334 also scrolls to the bottom for every change, regardless of whether the human has scrolled up.

A fictional warm median for the real thread/transcript projection was **0.41 ms at 100 turns, 4.16 ms at 1,000 and 33.00 ms at 10,000**, still displaying 40 rows. This excludes Markdown/layout/source visibility work. The broad projection can exceed a frame budget before rendering begins.

**Repair:** retain stable completed row projections, update the active reply independently, and derive a bounded visible window while preserving the preceding separator context. Follow streamed output only when the reader is already near the bottom. **Acceptance:** repeated deltas do not reproject all old rows; scrolling up remains stable; earlier-message pagination and dated separators remain correct.

## Further storage scaling issues

**One task change rewrites every project and note.** The main-actor [workspace persistence path](/Users/mylomichael/Documents/Developer/Mission%20Control/MissionControl/LifeWorkspaceStore.swift:232) validates and encodes the whole state. In fictional in-memory storage with 2,000-character notes, one status change wrote 229 KB / 2.31 MB / 11.56 MB at 100 / 1,000 / 5,000 items. Debug elapsed time was 2.55 / 17.10 / 88.87 ms; optimized time was 2.48 / 12.23 / 64.27 ms. Disk latency was excluded. Independently keyed item/note records and atomic operation receipts would bound write amplification. Move serialization behind a storage owner and publish committed UI snapshots; merely moving arbitrary mutable SwiftData objects between executors is not sufficient.

**Recently deleted records consume a permanent shared capacity.** [LifeWorkspaceRules.validate](/Users/mylomichael/Documents/Developer/Mission%20Control/MissionControl/LifeWorkspace.swift:185) caps all items at 5,000, including deleted history and other accounts. Deletion retains those records and the UI provides restoration without purge. An almost-empty active workspace can eventually fail to accept new tasks because of lifetime history. Separate the active index from retained archival/tombstone storage while preserving restoration identities and anti-resurrection rules. This is a future capacity boundary; no current personal count was inspected.

## Architecture and AI improvements

### Consolidate authority and execution state without a wholesale rewrite

The app has different paths for chat tools, prepared Review approval, direct native UI edits and completion. Their safety policies are similar but their implementations have diverged. Findings 1, 10 and 11 are examples of that divergence.

Use a shared typed operation lifecycle: prepared payload and exact targets, human authority, durable claim, mutation attempted, verified readback, completed receipt, supported Undo. Adapters should differ in how they obtain authority and present progress, while consuming the same execution contracts. Represent pre-save failure and uncertain save as separate states. Keep canonical operation IDs and durable uncertainty barriers throughout migration.

### Replace global invalidation with explicit relevant dependencies

Findings 6 and 12 show opposite costs of broad validation: unrelated facts remove useful history, and unrelated source changes interrupt valid work. Request dependencies should distinguish account/storage ownership, human permission, actual supplied evidence, and display metadata.

[PAConversationEngine.swift](/Users/mylomichael/Documents/Developer/Mission%20Control/MissionControl/PAConversationEngine.swift:35) invokes validation on every delta. Current validation constructs runtime projections and permitted source-memory sets. Use cheap ownership/revision signals during streaming, with exact relevant checks at inference, tool and save boundaries. Do not remove the final native write guard or make cached permission decisions authoritative after withdrawal. Measure callback time and main-thread work at larger memory/source sizes.

### Reduce repeated model calls and oversized capability context

[AssistantService.swift](/Users/mylomichael/Documents/Developer/Mission%20Control/MissionControl/AssistantService.swift:538) sends a large general instruction set and ordinary tool inventory across rounds. [PAToolAuthorization.swift](/Users/mylomichael/Documents/Developer/Mission%20Control/MissionControl/PAToolAuthorization.swift:7) adds a separate inference for each mutation. Multiple serial authorization calls can dominate a multi-action request.

Build deterministic schemas from available capabilities, keep a compact common policy, and evaluate one exact authorization pass for an already prepared batch. Dynamic capability selection must preserve essential read/preparation tools and avoid extra routing inference for trivial turns. Do not weaken human authority validation just to remove calls. Measure request count, input tokens, first-response time and verified end-to-end action latency on identical fictional scenarios before choosing an approach.

### Measure retrieval usefulness before adding a more complicated search system

Current [memory retrieval](/Users/mylomichael/Documents/Developer/Mission%20Control/MissionControl/PAMemory.swift:194) uses literal tokens and bounded typed connections. It can miss synonyms or paraphrases. A larger memory graph does not itself prove better recall.

Create held-out fictional cases for paraphrases, distractors, own-name collisions, corrections, expired evidence and source withdrawal. Compare the current selector with conservative aliases/stemming or a separate semantic candidate generator. Retain permission/evidence filtering before retrieval and exact dependencies afterward. Report relevant-fact precision/recall and whether the assistant successfully completes follow-ups; do not treat schema validity or number of recalled records as quality.

### Make optimized builds a routine acceptance tier

[build.sh](/Users/mylomichael/Documents/Developer/Mission%20Control/scripts/build.sh:22) explicitly selects Debug; [generate-project.py](/Users/mylomichael/Documents/Developer/Mission%20Control/scripts/generate-project.py:28) sets `-Onone`. That is useful for current evaluation modes, but it also adds runtime cost to normal candidates. The Focus comparison demonstrates that optimization helps while leaving structural bottlenecks.

Maintain a signed optimized candidate path with matching storage/signature identity and equivalent source-free safety coverage. Keep DEBUG-only evaluation binaries explicit. Compare production-equivalent behavior before changing the installed build configuration; this audit did not replace or launch the app.

### Strengthen tests around interactions and observable outcomes

The repository already has substantial regression coverage. Missing cases are disproportionately at boundaries: two loaded writers, future optional fields, receipt eviction, per-account discovery failures, permission expansion, callback cancellation, and stale native UI state. Add fixtures at those boundaries rather than adding more tests that restate a helper's implementation.

Automate the source-free suite on macOS and retain explicit separate native/model acceptance tiers. For AI behavior, keep a fixed fictional corpus covering ambiguous versus clear requests, clarification continuations, multi-action recovery and injected source changes. Measure semantic success independently from deterministic safety checks.

## Verification and limits

- All **65 source-free suites were attempted**. After rerunning SwiftData-dependent suites with the compiler access they require, **64 passed and one failed**. The initial sandbox macro-server failures were environment failures, not evidence of source defects.
- The remaining failure is [AdviceDependenciesChecks.swift:71](/Users/mylomichael/Documents/Developer/Mission%20Control/Tests/AdviceDependenciesChecks.swift:71). It changes only an assessment revision for an identical proposal and expects another suggestion. The current [deduplication rule](/Users/mylomichael/Documents/Developer/Mission%20Control/MissionControl/Proactive.swift:664) intentionally retains the original action identity; another current test explicitly expects this. Reconcile the stale assertion and separately test materially changed source/action content. Reintroducing duplicate suggestions to make this test pass would regress the current contract.
- Both existing performance suites passed. The actual runtime fixture reported **642 checks passed**. At 10,000 memories its cached pipeline measured about **381 ms cold / 89 ms warm**; changed-chunk conversation persistence at 10,000 turns measured about **29 ms warm**, writing two records. Existing caching/chunking helps; main-thread cost still grows with retained history.
- Additional fictional reproductions covered competing writers, opaque project fields, child restore, receipt eviction, added-chat baselines, unrelated-source learning invalidation, callback cancellation and WhatsApp publication amplification.
- No personal source bodies, saved personal data, credentials or live model requests were used. No Apple write, normal app launch, installation or product-code edit was performed. Native write findings are based on source paths and fictional boundary checks; physical recurrence/Undo behavior still needs disposable native acceptance during a repair.
- Timings describe these fixtures and build modes. They are not end-to-end personal-workload benchmarks and should be repeated under controlled load when validating fixes.

## Local reproduction evidence

Temporary artifacts are outside Git and may be removed by system cleanup:

- [Initial source-free run](/private/tmp/missioncontrol-check-9_mzo_5p/results.json), [first compiler-access rerun](/private/tmp/missioncontrol-check-pizzpezx/results.json), [remaining rerun](/private/tmp/missioncontrol-check-l6bi7q8v/results.json).
- [Existing performance suites](/private/tmp/missioncontrol-check-qxlqew7s/results.json).
- [Storage reproductions](/private/tmp/3po-storage-audit-b5lbhtgr/StorageAudit.swift), [Projects projection and save benchmark](/private/tmp/3po-storage-audit-b5lbhtgr/FocusBenchmark.swift).
- [Actual learning-service reproductions](/private/tmp/mc-audit-ai-x3dbw5dg/AuditChecks.swift).
- [Chat projection benchmark](/private/tmp/3po-audit-chat-projection.swift).

The existing untracked duplicate icon image was present before the audit and was left untouched.
