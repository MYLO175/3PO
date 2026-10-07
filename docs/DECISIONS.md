# Decisions

These are significant product choices, not a record of every code edit.

## Local native app

Calendar, Reminders, Mail, permissions and linked-device data require this Mac. The interface is native macOS, with local persistence and signed in-place updates. Cloud inference assists the app; it does not turn the project into a remotely running personal assistant.

## Tools for actions

Ordinary conversation expresses intent. Typed local tools resolve exact records and verify changes. Command-word templates are unnecessary; imported text and saved memory remain information rather than permission to change Apple records.

## One PA conversation with multi-area Focus

The latest user direction replaces named-topic navigation with a multi-select lens over life areas. Keep one ongoing general conversation; capture Focus on each request and use it to prioritise relevant memories. Focus is a relevance preference, not source access or write permission. Prior topic transcripts and drafts remain saved without merging or deletion; earlier topic memories become available to this account's Focus notebook while retaining their original evidence and tags. Legacy queued work retains its captured ownership.

## Memory must be inspectable and correctable

Direct statements and interpretations have different confidence. Stable human-stated facts should persist. Evidence and correction/forget controls matter more than graph density. The graph is a view over knowledge records, not the underlying proof of intelligence.

6 October transparency: use a read-only inspector over the existing store/projections, with saved/current/available/selected distinctions. Initial request selection and notebook input are assembled once and referenced by an optional ID/count trace on the existing assistant turn. Successful memory reads have a separate trace set; issued identities and conservative source-history dependencies keep their original safety roles. A trace is prepared input metadata, not model reasoning/attention, an exhaustive source audit or action success. Current access gates historical inspection; no duplicate prompt/source store or inference on opening.

## Separate facts, organisation and recall

Original evidence-backed facts are the authority. Life areas and typed endpoints are additive metadata; they can be reclassified without rewriting that evidence. Notes/maps derive from currently usable facts. Recall selects a bounded relevant subset and follows entity links without expanding through the universal self hub. These layers should not become a single ungrounded biography prompt.

Use one account-owned self identity, even when several labels refer to the human. Do not merge contacts by display name. Non-self alias/entity resolution remains a later reviewable capability. Starter areas are navigation scaffolding; a missing area is unexplored rather than absent.

## Corrections keep their evidence

An unambiguous human revision can correct memory through ordinary conversation. Create a new current version, retain the old wording/evidence, and exclude superseded beliefs from recall. Restore creates another version rather than erasing intervening history. Source discrepancies may prompt review but cannot silently override the human. Automatic semantic conflict detection/merging is a separate planned feature.

## Measure useful understanding

Keep deterministic ownership/history/retrieval checks separate from real model-quality checks. The manual subscription evaluator uses only fictional statements and disposable memory. Passing a focused scenario suite supports that scenario, not a claim that the PA knows a whole life or that live personal-source acceptance is complete.

## Selective background understanding

Assess meaningful new information and retrieve older sources when needed. Do not manufacture hundreds of historical email summaries. Background learning should be bounded, incremental and explain which sources it uses.

## Advice and drafts before external communication

Mail and WhatsApp remain read-only. The PA can recommend work and prepare local drafts for review/copy. It cannot send them. Tasks for you is the place for actionable suggestions and handoffs.

## Git plus a readable notebook

Git records implementation and documentation history. This docs folder explains the current system and next changes. PLAN carries detailed scope; STATUS carries engineering evidence. Personal life notes and source content do not belong in this repository. Obsidian can read the Markdown documentation, but adds no runtime dependency.

## Document update rule

A meaningful implementation should update the relevant explanation and roadmap item. A significant change of direction should add or revise a decision. Describe the resulting behaviour, distinguish planned from implemented, and retain verification limits.

## 5 October — Recurrence and deletion use native scope
The user asked for Apple-style recurrence functionality and equivalent PA control. Both entry points use EventKit, exact occurrence IDs and fresh exposed-field/revision readback; no title-based writes or simulated local recurrence. Calendar future-events scope includes the selected occurrence and preserves history. Reminders exposes one repeating task rather than pretending EventKit has Calendar-style reminder occurrence spans. Semantic human validation resolves explicit scope or asks one ambiguity question. Canonical persistent claims prevent replay after an uncertain write. Series edits/deletion have no claimed Undo; restoring multi-record recurrence history needs separate design. Keep specialised native alert metadata unchanged, and distinguish public API coverage from Apple-app parity.

## 5 October — 3PO branding
Use the user-selected top-left gold robot icon and 3PO as app/product/window name. Keep the existing bundle ID, Swift module and storage/registration/Keychain identities so this remains an update of the same app. Preserve the independent PA display-name preference. Use the supplied tile as a direct crop; no redesign.

## 5 October — Continuous navigation chrome
Use the sidebar palette role for the sidebar and native toolbar/window background, with a continuous rounded inset canvas boundary. Collapse to icons instead of removing navigation; retain the existing visibility preference, toolbar identifiers and menu controls. Dashboard geometry is recomputed for available space without modifying saved widget rectangles.

## 5 October — Left/top navigation colour only
User refined the sidebar treatment: remove right/bottom canvas inset and those corner masks. Keep only upper-left canvas rounding/top spacing, so sidebar colour forms an L rather than a frame.


## 5 October — Shared durable life structure alongside memory

Use a small typed local registry for enduring areas/courses/projects/work, rather than rebuilding Notion or deriving every identity from free-text memory. Stable IDs, one navigation parent and typed cross-links make manual widgets and PA edits act on the same objects. Memory retains its evidence and correction lineage; source pointers obey current permissions and Apple apps remain authoritative. Organisation and meaningful work state are separate from AI belief, and missing times/progress stay unknown. Store this as a separate versioned CachedDashboard payload, preserving existing SwiftData types, caches, layouts and conversations. Foreground semantic human intent, fresh revisions and atomic operation receipts govern PA changes; no additional background inference is enabled.


## 5 October — New-project placement and shared identity projection

User approved three project creation routes with automatic life-map placement and cross-links. Creation is an explicit bounded organisation request, not a trigger for general source learning or standing work-state writes. Save the project first, then run one serial subscription pass over saved same-scope structure and usable human facts. Respect a chosen parent; ask one question only for meaningful ambiguity. Typed known organisations/courses can provide stable candidate anchors, but materialise only the selected paths. Keep exact identity metadata and parent/cross-link placement separate from original facts, evidence and user-written headings. Project/Map/PA share a read-only canonical projection, with conservative name matching and durable explicit bindings rather than rewriting memory. Interrupted/failed requests pause; refresh never creates a request.

## 6 October — Incremental local Mail access

Replace hourly invalidation of the entire 30-day day index and two-second recursive drainage with persisted per-account arrival watermarks and a separate bounded cache/audit lane. Ten-minute overlap tolerates delivery/clock edges; immutable pending ranges preserve interruption recovery. Continue to use the existing read-only signed Apple Mail helper rather than introducing a second email login, credentials or private Mail database access. Bulk date-filtered ID reads avoid one Apple event per message just to enumerate an inbox. Failures back off per account and never prove an empty source. Read-only keyword expansion may correct human spelling; literal current-human evidence remains a write requirement, not a prerequisite for a header lookup. No extra background AI or historical summary sweep.

## 6 October — Identity-based Mail checks and source-first heartbeat
Received dates are not local arrival cursors: late synced mail can fall behind a timestamp watermark. Each arrival scan now compares exact native/internet identities across at least 48 hours and hydrates only differences. Keep month cache and older bounded audits instead of rebuilding history. A 30-minute app-owned heartbeat refreshes before conditional assessment, with changed-content fingerprints, persistent pause/account ownership, existing evidence guards and at-most-once private notification claims. It replaces minute Mail polling and separate five-minute email processing; ordinary Refresh stays no-AI. This heartbeat runs locally while the app is active, not as a Codex scheduled automation.

Live heartbeat validation found a repeated older deadline. Keep heartbeat email candidates within48hours and compare cited original email IDs locally against today's usable brief, excluding unchanged assessments already covered. No daily brief prose is added to a heartbeat inference payload. Preserve existing deliveries and require substantive new evidence for future interruption.


## 6 October — Human project ownership and independent heartbeat

Projects and their authored content belong to the human. Ordinary facts learn life context; only an explicit workspace request or accepted concrete proposal creates/edits project content. The PA can organise supported life anchors and place/link an existing project without inventing work. Tombstones preserve recovery and prevent background resurrection. Structure, Map and notebook share stable record identity; matching is reviewed, never a silent fuzzy merge.

Collection and thought have independent clocks: local Mail collection every five minutes, received WhatsApp cache between checks, configurable hourly AI heartbeat. A persisted whole-run request allowance charges each actual assessment request; limits leave pending work and do not interrupt collection. Morning brief priority retains its original daily identity. The continuous transcript remains saved while display and inference history are independently bounded, with human dialogue protected from background update volume.


## 6 October — Keep actual failure reasons with the reply

A generated explanation is not an execution trace. New PA replies retain bounded original tool errors locally, and pre-operation intent refusals identify that no native save was attempted. Existing receipts still govern uncertain saves and prevent replay. Older replies are preserved without invented retrospective diagnostics. Source-relative timing is resolved before proposing a write; the human request remains its authority.


## 6 October — Keep internal tracking out of native notes

Operation identity belongs in private local receipts. A Calendar event or Reminder’s notes contain requested content or stay blank; default request hashes are removed from both current and legacy creation adapters. Existing marker cleanup is an explicit, receipt-and-native-ID-bound notes edit, never a title search or background migration. Disposable validation markers are supplied explicitly and confined to fixtures.


## 6 October — Explicit pasted images in the PA

Image input extends the existing subscription tool loop, not a separate generation service. Clipboard inspection occurs only on Paste, with a removable local preview before Send/Queue. Native readable pasteboard types must include images so AppKit enables the Paste menu; ordinary text editing/Undo stays native.

Optional small references preserve legacy transcripts/drafts/queues; bytes are private separate files so routine cache scans do not load screenshots. Account and digest checks guard display and requests. Current images are mandatory; older replay images have an independent four-image/eight-MB bound and visible omission labels. Text/tool context retains its previous bound. Screenshot text remains imported data and cannot independently authorise writes or human-memory corrections. Background processing is unchanged.


## 6 October — Foreground completion has no work-count cap

A human-requested Calendar import must not stop after four changes or an arbitrary number of tool rounds/calls. Remove those foreground counters and the two-page Mail continuation counter. Preserve the actual authority, ownership, revision, cancellation and duplicate-save checks. Diagnostic fixtures remain finite; automatic heartbeat/learning allowances are separate.

Recent completed reasoning/function/output rounds stay together. When transport context needs room, omit oldest complete rounds and provide bounded receipt progress data; durable receipts and session-issued native identities are retained. Stop only a genuinely stalled sequence of three identical argument/result rounds, not a numerical amount of useful work. This extends future requests without replaying the user's previously incomplete import.

## 6 October — Plan the PA around changing commitments and durable knowledge

The requested direction is a personal assistant and custom project workspace that can follow communications, learn useful context and eventually reason offline. The architecture review recommends preserving the native app and verified tools while joining currently separate learning/summary/suggestion paths through explicit source coverage, temporal evidence and shared commitment identities. Source collection and assessment progress need separate records; selective sampling must not imply complete understanding.

Knowledge, workspace identity and action authority belong to the app rather than model weights or subscription authentication. A stable local profile and replaceable inference adapter are proposed foundations for local mode. Graph mail is a feasibility-tested candidate, not an enabled integration; Reminders-backed task bindings, automatic recovery and any standing native-write policy need distinct delivery and validation. These are design recommendations recorded in [PA architecture review](PA_ARCHITECTURE_REVIEW.md), with no runtime or personal-state change in this review.


## 6 October — Clear controls and measured understanding

Keep Cambridge email on the existing read-only Mail bridge because tenant consent blocks Graph; offline inference is later. Reminders remains native truth for to-do/shopping, with project bindings improved incrementally. Research supports evidence and chronology plus measured retrieval, not a universally best memory vendor/graph. Retain raw evidence/corrections and distinguish lasting knowledge, temporary claims and job context; full episodes/commitment lifecycle and cross-source quality evaluation remain next units.

Use native Settings sections and Help, call the product behaviour Background review, and separate interval/useful-message limit from the advanced communication-call budget and ChatGPT allowance. Record actual 3PO request metadata centrally, with missing tokens unknown and no invented remaining percentage. Provider token details are subsets, not additional totals. No prompts/source content/credentials enter the usage ledger.

Separate WhatsApp collection from assessed versions. Retain bounded waiting opaque references; allocate fairly across chats; advance only completed validated batches. Treat legacy orientation cursors as unverified baseline without replay. Disclose expired/unavailable versions and keep failures paused. Hash scope/chat keys and capture monotonic context/learning changes to reject off/on races. Preserve existing quotas, selected chats, permission boundaries and no-AI Refresh/reception. This queue belongs to source learning; do not imply every brief/suggestion/email has a unified assessment queue yet.

## 6 October — Source reports evolve without becoming human authority

The audit found that a later WhatsApp cancellation could leave an earlier plan as a separate usable memory. Add same-conversation provisional version updates and bounded multi-quote evidence first. Preserve original records and exact source revisions; retain attributed proposed/accepted/changed/cancelled/completed/unknown states. Source-reported completion never updates an Apple item. Protect human-confirmed/human-origin and manually pinned records, and require newer evidence plus an issued current source-memory ID. Cross-source or equal-name identity matching remains a separate evaluated feature.

Supply bounded recent neighbours/latest reports and already-permitted saved quotations, without scanning historical sources. Only assessment targets advance coverage or become primary facts. Every supporting version gates recall; missing evidence must not resurrect an older plan. Forget also excludes dependent source beliefs, while Undo restores the specifically removed evidence. Save opaque per-version assessment receipts with facts, including empty valid assessments, so separate cursor failure cannot cause paraphrased duplicate extraction. Retain existing no-AI collection and automatic quotas. Automatic Tasks/brief memory inputs remain human-only until their persistent dependency guards are extended.


## 7 October — Retire context without splitting the brain

Keep one evidence-backed notebook projection for the Life map, PA recall and human-owned workspace. Bring durable workspace bindings into the existing ranker rather than maintaining another project-memory database. A matching current project/item label can select its current associated facts; exact references follow a usable correction lineage without rewriting the saved pointer or asserting a new identity. Ambiguous names never merge, tombstoned projects do not project, and unavailable facts stay unavailable.

Add optional human-context retirement independently of commitment resolution and source invalidation/Forget. Retire preserves evidence and IDs; Restore is a local human review. It cannot mutate projects or complete Apple items. Suppress re-extraction of the same retired human evidence, while leaving original dialogue intact.

Existing-fact organisation may reconsider unpinned classifications after 30 days with the original eight-fact/two-pass limits and shared learning allowance. Treat this interval as an initial conservative product choice, not a benchmark-derived optimum. Supply prior classification as metadata, favour stability, and keep classification review separate from evidence age/confirmation. No automatic semantic deletion or newly enabled source ingestion is introduced. The primary research and limitations supporting selective, temporal, evidence-backed memory are linked in MEMORY_AND_CONTEXT.md.

## 7 October — bounded native evidence and proposed maintenance

Reuse existing source collection and validated Mail quotation assessments rather than run a second historical index or persist full Mail bodies. Independent account opt-ins default off, establish baselines and keep opaque cursors/assessment receipts. Distinguish item dates from content revisions/observations. Native replacement requires exact current identity/new revision and issued old evidence; previous quotations remain version history. Calendar uses separate memory identity without changing dashboard/native-write IDs; recurring external IDs plus original occurrence date and collision abstention preserve occurrence boundaries. Apple documents [original occurrence-date stability](https://developer.apple.com/documentation/eventkit/ekevent/occurrencedate) and [local identifier sync limitations](https://developer.apple.com/documentation/eventkit/ekcalendaritem/calendaritemidentifier); provider identity drift is unknown, never a title-based match.

Semantic review produces proposals instead of executing merges or choosing a winner. Only human facts are supplied; retirement proposals require old unconfirmed situational non-commitment context with unpinned metadata. Exact record fingerprints guard every proposal; original evidence/projects stay authoritative. Weekly review is optional and shares the existing learning allowance, with eight seeds/24 total facts/30 KB and at most six proposals. Actual identity aliases, cross-source conflicts and source-aware Tasks/brief dependencies remain independent work.


## 7 October — Advice carries its supporting context

Enable permitted source facts in briefs/Tasks only together with persisted exact belief receipts and current-purpose permission checks. Capture and validate the same production selection; exclude organisation/review bookkeeping from persisted truth fingerprints so metadata maintenance does not churn saved advice. Every supplied fact is conservatively tracked; no claim of observed model attention.

Mail headers must match the current assessment, with exact assessment/body/reply receipts for new advice. For WhatsApp, an unchanged original request is insufficient when a later reply may cancel it: compare the selected cache during inference and retain per-supporting-chat receipts. Cache loss means unavailable, not completion. This conservative rule can invalidate advice on an unrelated reply in the same chat; semantic episode identity is a measured next unit.

Keep original morning records/claims and visible transcript history. Show dated saved advice with a freshness explanation, omit unusable prose from new inference and require current support at native/project review. Do not automatically replay unchanged historical suggestions. No new source access, opt-in, sending, write authority or AI-on-Refresh is introduced.


## 7 October — Explicit plan identities and actual Life map items

A source ID identifies one provider item/message, not a real-world commitment. Shared titles, names and dates are insufficient for cross-source identity. Add optional human-reviewed commitment group/revision metadata on existing facts, without merging facts, copying another knowledge store or weakening exact source versioning. The local review requires exact current permitted IDs, same account/scope and a captured revision; two existing groups cannot implicitly merge. Validated supersessions and same-scope human commitment corrections inherit identity; source models cannot assign it.

PA/brief/suggestion context derives a small plan index from the same selected facts. Mixed states remain uncertain; independent claims stay separate. Central current-group signatures exclude review/classification bookkeeping but include membership, evidence, version, resolution and invalidation so a connected report's change invalidates advice based on other members. There is no automatic latest-wins rule or native/project completion. Rich canonical temporal episodes and natural-language connection tools are deferred.

Life map counts and drilldown resolve the same durable workspace IDs. Area sheets distinguish saved entries from remembered concepts/facts and navigate into the existing project browser within the sheet. This avoids a second fragile item sheet and keeps Back, original saved widget roots and source ownership intact.


## 7 October — Background output belongs in Review inbox

Use the existing Tasks widget/store rather than another output database or normal chat delivery. Keep saved widget IDs/layouts and historical chat. Useful outputs have no daily count cap; inference still has explicit request/source/payload bounds, pending progress and pause rules. A review interval controls communication comparisons, not every background job.

Permit an inferred native date-change proposal without a prior confirmed memory connection when distinctive evidence supports the match. Keep inference and authority separate: exact quote, exact issued native snapshot, proposed date/timezone and explanation. Following the user's clarification, Approve directly applies the displayed date change; Dismiss leaves native data unchanged, with View/edit available before approval. Repeating items retain explicit occurrence/series review. A pending claim precedes Apple mutation and an additional fresh revision check follows the actor hop. Known pre-save failures can clear the claim; uncertain saves cannot replay. No automatic memory-group merge, project authoring, cancellation/deletion/completion or Apple changes.

Persist assessed source-version receipts even for quiet comparisons. At the three-result response bound, leave other sources pending instead of silently declaring the whole input handled. Receipts depend on current native/memory/source/model/timezone context, enabling reconsideration of recent changed context without a history sweep. This improves bounded coverage; it does not prove sustained scheduler reliability or introduce a global job coordinator.

## 7 October — Mail outages isolate source work, not all communication review

The live iCloud timeout demonstrated that independent collection was being cancelled out by the coordinator's all-source barrier. Capture fresh completed arrival windows per Mail account and assess only those accounts, with current header/account guards at each consumer. Preserve failed/unfinished account cursors, cache, backoff and pending assessment; never convert partial coverage into a clean inbox claim. Save per-registration account review status separately from shared request allowance and existing per-message decisions/version receipts.

A local Mail body-read failure is a source issue, so exclude that account for the remaining run and allow other checked accounts to finish. An inference/transport/persistence failure remains paused and needs explicit continuation. Require fresh native data before plan comparison while allowing selective email classification to finish independently. Source-aware comparison memory follows the captured account lens and WhatsApp acknowledgement; body classification uses human memory until it has its own source-memory receipts. Expose the existing email-assessment control in Background without changing stored settings. Keep the existing serial coordinator, bounded reads and review-only native changes; concurrency, global arbitration and sustained recovery remain separate work.

The live comparison reached inference but failed strict evidence validation. Mail comparison now issues references to its already validated primary/date quotations and resolves the model's chosen reference locally. Do not loosen quote matching: reject unknown/cross-source references or conflicting text; WhatsApp retains its exact-quote path. This addresses Mail quote copying, not all matching/validation failures. The failed personal review remains paused; a separate fictional subscription check verifies reference selection without replaying it.


## 7 October — Separate preference, planning and completion

Prepare useful email replies within the existing selective body assessment and communication-review budget, and show them inline. Backfill missing drafts from retained assessments without restarting Mail indexing. Suppress no-reply/external-action drafts, preserve human edits, retain placeholders and reject stale results. Drafting stays local review/copy only.

Learn from bounded actual dismissal examples rather than permanent sender rules. Repeated content is a stronger weak signal; a new request/deadline can still surface. Retain dated examples for 90 days and let Undo remove the signal. Saved actionable email can be reconsidered after native/context changes even beyond the recent informational-source window, using existing current-header/scope checks and capped batches.

Treat Calendar/incomplete Reminders as planned and exact recently completed Reminders as addressed. Use reversible inferred attention associations, separate from human-confirmed commitment identities and Apple-write receipts. Match every requested action; decline ambiguous/common-name matches, conflicting dates and missing completion evidence. Current native revision, permission, account and dependency checks invalidate associations conservatively. Provide Keep in review as a human override. Persist short communication activity receipts for inspectability without copying source bodies or reasoning into another log. Sustained scheduling and multi-turn proposal quality still require measurement.

## 7 October — Source quotations do not prove date interpretation

One explicitly resumed live review completed, but interpreted a numbered course week as today's deadline without a supplied date anchor. Keep exact quote validation and add a conservative local numbered-week safeguard alongside inference instructions. New classifications keep the date unknown; new proposals become clarification updates. Project unapproved historical output safely without rewriting its original evidence or approval receipt. Safe email projections retain the original assessment revision, so source inspections and existing ownership guards remain meaningful; this transient receipt is excluded from persistence. Decline planned/addressed hiding for these uncertain assessments. Do not guess a university calendar, repeat the personal inference or modify native plans to repair the observation. Broader temporal grounding still needs measured work.

Flatten the Background activity sheet's native grouping while keeping titled sections and contained accessibility children. The observed failure was in the external inspection helper; 3PO's event loop remained responsive. The revised sheet was inspected and scrolled successfully. Do not equate that fix with sustained scheduler acceptance.

## 7 October — Separate deferred collection from interrupted inference

A missed start must not consume the user's review interval. Check inference availability and foreground activity before collection; persist bounded retry timing after an interrupted source-only collection or a foreground delay after collection. Recover unfinished collection as pending idle work, while committed assessment remains paused for explicit resume. Preserve account lanes, source cursors, request claims and completed run identities in both cases.

App-allowance waits persist until the next local calendar day, with explicit allowance increases and timezone changes able to release them. Final request claims recheck captured registration, local day, control revision, parent cancellation and foreground typing before saving a call receipt. Quiet checks may clear stale pending flags only for available completed coverage; they do not claim AI assessment, reset calls or unpause inference.

Expose due/retry/wait state in the existing inspectors without new inference or controls. Do not show another account's transient status. Unreadable saved review state remains preserved and blocks scheduling. Keep the source-first collector and existing serial workers rather than treating this increment as a global scheduler replacement. Fictional multi-day receipts and actual compiled guard/recovery diagnostics complement live automatic review; prolonged real sleep/wake and quality acceptance remain separate.

## 7 October — A failed AI check is not an Apple service failure

The actual saved failure was server_is_overloaded from ChatGPT during source-free intent validation, before any native operation. The subsequent explanation incorrectly blamed Reminders. Distinguish an unavailable/invalid check from an actual refused decision. Unavailable checks terminate the turn with a local explanation and retain prior successful receipts; no next inference round, remaining mutations, queue advancement, automatic retry or approval bypass. Keep cancellation and captured ownership guards.

Move existing native source/details prerequisites before intent inference so an incomplete tool plan does not spend a needless check. Preserve exact issued IDs, full revisions, canonical receipts, readback and Undo. Recognise the explicit overload code without marking quota exhaustion or clearing sign-in. Only the narrowly recognised historical no-change misattribution with an app-generated pre-operation overload receipt gets a transient corrected display/history; never replace partial-success receipts or saved original records.
