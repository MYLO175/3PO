# Building a useful personal assistant

Memory acceptance plan approved 4 October 2026, with subsequent dated corrections below. This plan concerns the PA's understanding, memory, reasoning and useful behaviour. Current requested Memory, Projects and Appearance work may use separate development streams; this plan does not independently defer a newly requested appearance task. No model training, paid API/embedding service, hosted agent migration or new source permission is required for the initial work.

## Current checkpoint — 8 October

Implemented foundations include one general conversation with multi-area Focus, exact current-belief/source-permission gates, inspectable evidence/history, bounded native/WhatsApp source learning, human-reviewed plan links and persistent advice dependencies. Targeted recall is lexical/typed-link/exact human-binding selection, permits zero facts and does not always inject unrelated identity/preferences. Notebook facts share the selected IDs. Projects creates only Space/Task while preserving rich memory entity types and legacy IDs. Semantic aliases, embeddings, actual consolidation and broad cross-source episode understanding remain separate uncompleted units.

Use [MEMORY_AND_CONTEXT](MEMORY_AND_CONTEXT.md) for current selection contracts, [VALIDATION](../VALIDATION.md) for evidence/limits and the top of [STATUS](../STATUS.md) for the latest checkpoint. Older dated implementation notes below are history where later corrections supersede them. Heartbeat recovery does not override paused memory-learning claims or foreground queues.

## What good means

The PA should maintain a useful, inspectable model of a person's life, retrieve the parts relevant to a task, notice supported connections and act through the existing verified tools. A colourful/dense graph is not evidence of understanding. Success is measured by correct answers, corrections that stick, useful suggestions and fewer repeated questions. Uncertainty, unavailable sources and incomplete history must remain visible.

Example acceptance cases use fictional people/data: a person identifies themselves once; a family group's alias is recalled in a later conversation; a project is connected to an explicitly stated goal; study focus recalls modules/project and relevant career context; a changed goal supersedes its old version; an old temporary plan is not mistaken for a current commitment; two contacts with the same first name remain distinct; unrelated topic/account facts remain private; imported instructions cannot trigger an Apple write.

## 1. Identity and evidence foundations

6 October transparency increment: the [Memory and context guide](MEMORY_AND_CONTEXT.md) and shared native inspector explain the existing structure, original evidence, current/usable selection gates and remaining gaps. New foreground replies retain prepared-input identities/counts on their existing turn; local recall preview uses the production ranker. This adds inspectability without a second knowledge store, semantic retrieval, new source learning or any change to action authority. STATUS records focused checks and live visual limits.

Use one stable self identity per subscription registration, independent of display name. Resolve first-person references to that identity. A named subject becomes self only through an explicit identity annotation supported by an existing human fact, never because the name matches a contact. Keep source IDs, original evidence, scope, certainty, dates and memory IDs. Organisation is additive metadata; do not rewrite/delete saved facts during migration.

Create typed entities for people, groups, organisations, places, roles, courses, projects, goals, habits, interests, values and personality traits. Existing ambiguous labels remain concepts until classified. Aliases require an explicit supported identity link. Non-self people are not globally merged by display name. Account/topic filters run before identity resolution, graph projection and retrieval.

Acceptance: stable IDs across save/relaunch, legacy JSON decode, Mylo/You-style self mentions unified only with supported annotations, duplicate contact-name refusal and scope isolation. Use fictional names in fixtures; no personal facts in Git.

## 2. Organised life notebook

Provide flexible broad areas such as About me, Studies, Career, Personal projects, Interests, Wellbeing, People, Home and Administration. An area is a navigation/retrieval grouping, not a fact that the person has that activity. Hide empty areas. Facts/entities can belong to several areas and keep cross-links. User corrections to organisation take priority.

Store per-fact areas and typed connection endpoints with references to the unchanged source memory. Generate concise evidence-linked area notes from usable facts, with bounded coverage. Separate identities, values/preferences, goals, projects and temporary commitments. Organisation tools may classify existing facts but cannot invent a fact or mark a real-world task done. Explicit self-name annotations require direct human evidence.

Acceptance: project has a meaningful area; goals/habits retain their kind; multi-area links do not duplicate facts; notes link back to evidence; forgotten/resolved/expired memories disappear from projections and retrieval.

## 3. Retrieval that connects relevant context

Supply relevant permitted facts and matching notebook context within a byte/count budget. Broad life/day orientation may include identity/preferences; targeted tasks must not fill their budget with unrelated facts. Find graph neighbours by entity IDs, excluding the universal self hub from expansion so every query does not pull in the whole life. Keep confidence/freshness visible. Tools can request another area/entity when more detail is needed; original source readers supply fresh Calendar/Reminders/Mail/selected WhatsApp information when needed.

One ongoing general conversation uses multi-select LifeArea Focus as a relevance lens. Preserve earlier topic transcripts/drafts and captured legacy queue scope without merging or deleting them; this account's usable legacy topic memories are available to the current Focus notebook. Focus must never override explicit questions, broaden source permissions or expose another account's records. Start with deterministic local retrieval and measured recall; add semantic search only if tests show a real need and an authorised runtime is available.

Acceptance: study question finds old relevant project facts despite many newer unrelated notes; self-hub does not cause global expansion; explicit out-of-focus question still works; bytes stay bounded; excluded account/topic/source records are absent.

## 4. Adaptive setup and ongoing learning

Dedicated setup keeps small questions, own transcript/draft and explicit Start/Next/Skip/Finish. Use the organised notebook to distinguish known, uncertain and unexplored areas. Explore breadth across turns before drilling into the first disclosed role. Do not mistake a missing record for proof that an area is absent. Retain facts and classify them quietly before the next question, using typed tools with original human evidence.

Bounded conversation learning can attach the same organisation metadata. Existing-memory organisation is a separate resumable small batch, with captured account/topic/revision ownership, explicit manual start and independently explained automatic control. Paused/interrupted work never restarts silently. Questions should address uncertainty that would affect helpfulness; keep existing daily question budget and dismissal/Undo.

Acceptance: known name/course is not repeatedly requested; skip changes direction; ordinary task chat is unaffected; cancelled inference cannot commit late metadata; memory-off/usage pause remains honest.

## 5. Conservative maintenance and corrections

Detect possible duplicates/conflicts using structure, not just identical prose. Human corrections supersede supported old beliefs through reversible records, retaining history/evidence. Do not automatically overwrite confirmed facts. Review uncertain identity merges. Distinguish expired information from completed work. Forgetting suppresses relearning from the same human/source evidence and invalidates derived notes/indexes.

Acceptance: corrected fact wins recall; old evidence remains inspectable; forgetting a fact removes its entities/links unless other valid evidence remains; consolidation never changes scope or promotes an interpretation into truth.

## 6. Selective source understanding

Introduce a separate explained opt-in for learning from source deltas; foreground read access does not implicitly enable it. Calendar/Reminders changes, selected new Mail and explicitly selected WhatsApp text may yield provisional facts/projects/deadlines. Read only bounded recent changes; preserve source identity, revision, date, truncation and honest partial coverage. No full history sweep, sending, read receipts or inference from normal refresh.

Maintain account/linked-device/source-selection cursors and a bounded shared background scheduler. Capture scope before every request; reject late output when permission/identity changes. Source beliefs cannot authorise Apple writes or silently override human assertions. Deleted/edited/excluded sources invalidate dependent proposed context. Avoid unnecessary sensitive facts and third-party biographies.

Acceptance: synthetic incoming source reveals a supported deadline/project; changed/excluded source retracts its derived proposal; no old-inbox flood; quota/network failure pauses rather than retries/bills.

## 7. Reasoning, quiet suggestions and background handoffs

Use the notebook to compare source-backed future events/commitments with current Calendar/Reminders. A gap is a candidate, not certainty that something was missed. Rank importance using stated goals, deadlines, recent interactions and prior dismissals. State why a suggestion matters and link evidence; limit interruptions and deduplicate. Concrete accepted suggestions use normal task tools, with fresh identity/revision checks.

Queued requests run with captured thread/account ownership and produce inspectable handoffs. Email responses remain local drafts for review/copy, never sending or writing Mail. Use one short clarification/button choice only for real ambiguity. Keep briefs concise and relevant to the day; do not turn memory maintenance into daily notification spam.

Acceptance: a supported important deadline produces one useful suggestion; promotional content stays quiet; accepted suggestion creates one verified item; repeated runs do not duplicate it; queued interruptions are retained without automatic mutation replay.

## 8. Inspectable notebook, map and quality evaluation

Life map uses the notebook's areas and typed entities, with colour families, expandable hubs and cross-links. Provide a readable Notes view and evidence inspection. Map selection focuses the relevant notes; topic selection focuses retrieval. 3D is deferred until the 2D map and recall are useful.

Run a fixed synthetic scenario suite covering identity, evidence, organisation, retrieval, correction, ambiguity, scope, chronology, injection and budget limits. Distinguish deterministic fixture success from actual model/inference quality. Maintain a repeatable subscription-backed evaluator using dummy data and explicit manual runs; never place personal traces in Git or silently spend allowance on benchmark jobs. Compare before/after recall/action outcomes, not node counts.

## Delivery order and honest boundaries

Implement 1–4 and the useful notebook/map parts of8 first, with focused fixtures, compilation, signed in-place installation and documented acceptance. Then conservative maintenance5 and source learning6, followed by expanded proactive reasoning7. Each unit must preserve the existing transcripts/drafts/layouts, enabled scopes, subscription identity and receipts. Save validated local checkpoints and clearly record which phases are implemented versus planned in STATUS and the readable notebook. Continue meaningful authorised work within usage; no credits/resets/billing/delegation required. Live prompts requiring the human remain explicit blockers, not assumed consent.

## First implementation checkpoint — 4 October

| Phase | Delivered in this checkpoint | Still to deliver |
| --- | --- | --- |
| 1 Identity/evidence | One scoped self node, supported own-name label, typed endpoints, conservative contact separation; legacy records preserved | Reusable non-self entity registry and explicit supported aliases |
| 2 Notebook | Starter life areas, cross-area facts, typed goals/habits/values/traits, evidence-linked Notes and manual organisation pins | Custom subareas and genuinely useful generated hub summaries |
| 3 Retrieval | Local relevance plus two entity hops, self excluded as a bridge, bounded area context, optional topic-area bias | More precise topic anchors; semantic search only if measured gaps justify it |
| 4 Learning/setup | Inline organisation in conversational learning; rich-turn facts; dedicated breadth-first setup; small idle classification of existing human memory | Multi-turn interview/skip quality evaluation and source-driven questions |
| 5 Maintenance | Versioned human corrections, Restore, current-belief Forget/Undo, old-evidence relearning protection | Automatic semantic duplicate/conflict proposals and reversible consolidation |
| 6 Source understanding | Separate opt-in recent selected WhatsApp learning; typed source evidence/revisions; bounded paused cursors; source permission/freshness filtering; shared learning quota | Mail/Calendar/Reminders delta ingestion; source-aware automatic briefing/suggestion artifacts; broader live acceptance |
| 7 Useful behaviour | Existing queue, handoffs, briefs and quiet suggestions retained; they receive current structured memory | Better goal-based ranking and realistic source-to-suggestion evaluations |
| 8 Inspection/evaluation | Balanced adaptive area map/notes, source-fact inspection, deterministic scenario checks and actual subscription classifier/recall/interview evaluation | Live personal-profile visual acceptance, broader multi-turn/source/action suite, later 3D only if useful |

The first expanded live evaluation exposed weak interview organisation despite valid fact saves: 23/25 checks passed. Setup now offers the structured context saver rather than the overlapping legacy simple-save tool, and explicitly favours breadth and obvious supported metadata. The revised production-tool evaluation passed 25/25 using the app's existing selected subscription model (`gpt-5.6-sol`); settings were not changed. It retained four distinct fictional facts in About me, Studies, People and Personal projects, linked the project to its stated goal, and asked one focused next question. Saves used a disposable in-memory store and left real memory untouched. This is a focused scenario result, not proof of complete life understanding or live personal-source acceptance. See STATUS for exact build/install/fixture evidence.

Next substantive unit: extend phase6 beyond its initial WhatsApp implementation, measuring source quality and keeping permissions, evidence and artifact invalidation intact. Keep phases5/7's semantic consolidation and ranking changes independently measurable. Icon/toolbar/Settings polish remains deferred as requested.

Final expanded pipeline evaluation:27/27passed on4October, including actual production memory read/correction and the bounded existing-fact classification path when optional inline metadata is omitted. The final app is signed and installed; normal process launch verified. The intermediate repeat26/27result preserved the name fact but lacked its optional graph label, demonstrating why a separate evidence-preserving organisation pass is useful. Live personal/source acceptance remains separate.


## 4 October continuation: source understanding and map usability

The first source-learning implementation is deliberately selective: a separate `learnContext` opt-in in the encrypted, registration/linked-identity-scoped WhatsApp access settings. Foreground reading and brief inclusion remain independent. The app's idle scheduler can inspect up to eight recent messages, within the last48hours and a12KB source-text budget; the complete input is capped at24KB. First orientation skips the remaining recent backlog rather than producing a feed of historical summaries. Subsequent passes use message-identity/content-version cursors. Only current selected chats are supplied.

Up to four concise provisional/situational facts can be saved atomically with the exact quotation, message/chat/linked identity, source date and content revision. Source participants are not treated as the owner; no source statement can authorise an Apple change, overwrite human memory, establish the owner's name or become a confirmed preference. New source facts are eligible for foreground recall and the notebook only while their original cached version and selected access still match. A missing cached message means unavailable evidence, not proof that it was deleted or a task completed. Original records remain locally reviewable. Forget suppresses relearning from the same source version; human corrections create independent human evidence while retaining history.

Conversation learning, notebook organisation and source learning now share a persisted ceiling of four automatic passes per local day, with30minutes between claims. Their existing tighter limits and interrupted-job pauses remain. Manual checks are separately bounded. Briefs, email assessments and proactive discovery retain their own existing limits; this is not a claim that every background AI job has a single global quota.

Source-derived memories are initially excluded from automatic briefs/proactive memory inputs until those saved outputs carry source-memory dependency information. Foreground replies carry optional source-memory dependencies and are omitted from later AI history if those beliefs lose current permission/evidence. Local transcript text is preserved. Mail/Calendar/Reminders source learning, richer inferred connections, semantic conflicts/consolidation and source-to-suggestion ranking remain upcoming.

The map uses one owner and balanced coloured area hubs, with labels clear of branch paths, highlighted shared-fact areas and a compact single-spine layout. The 3PO preset supplies complete light/dark gold/ivory/bronze profiles; selecting it is optional and does not replace current colours on install. A local PA display-name preference changes the header, composer and foreground identity while preserving all storage/thread/widget IDs.


### 7 October — Organisation and lifecycle follow-through

Added human-controlled Retire/Restore for current human preferences/context, current-fact project associations in production retrieval, correction-aware exact bindings, and conservative reconsideration of unpinned classifications. The Life map and project details remain projections of the same permitted notebook. Focused fictional checks must establish: rename/correction recall under distractors, retirement/restart/Restore retaining original evidence and project state, source/commitment separation, same-evidence relearning protection, metadata review not renewing truth, manual pin protection, ambiguity/deletion exclusion and legacy optional-field decode.

Phase5 now has bounded duplicate/conflict/retirement proposals for human review; actual consolidation and aliases remain open. Phase6 now has separate default-off Calendar/Reminders/Mail cached-evidence learning lanes, baseline/delta coverage and native same-item history. Broader source coverage and sustained scheduling remain open; request context alone still does not mean assessed lasting knowledge. A graph display, number of saved facts or a successful compile is not acceptance of overall PA intelligence.

### 7 October — native-source adapters and reviewable maintenance

See [Memory and context](MEMORY_AND_CONTEXT.md) for current bounds/identities/permissions. New native source lanes use only fresh already-collected data and exact retained Mail quotes, share the persisted learning budget and preserve pause/recovery. Source refresh never initiates learning. Optional weekly review uses eight human-fact seeds plus bounded lexical neighbours (24 facts/30 KB) and at most six proposals; it cannot modify facts/projects. Confirmed/stable facts, commitments and pinned metadata cannot become retirement candidates. Fact-revision changes invalidate a proposal. Native occurrence stability, partial coverage, absent/returning versions, old Mail body edits, quota survival and actual subscription extraction need distinct acceptance, not a compile-only intelligence claim.


### 7 October — Source-dependent advice projections

Phase6/7 now supplies permitted source memory to new automatic briefs and proactive suggestions, with persistent exact selected-belief dependencies, purpose consent, Mail assessment/body/reply versions and supporting WhatsApp chat-cache receipts. Phase8 adds actual supplied-memory evidence panels to these outputs. Dated morning history remains immutable; current/history/recovery/review projections reject unavailable support. Organisation alone and unrelated facts do not invalidate saved outputs.

Acceptance covers revocation/version changes, correction/Forget/cancellation, unrelated fact/metadata stability, feature-specific WhatsApp consent, changed Mail headers with old assessments, new same-chat cancellation, legacy decode and preserved morning/update/notification identities. These checks do not establish shared cross-source episode identity, semantic aliases, real scheduler-race acceptance or broad inference quality. Continue with the cross-email/WhatsApp timeline and measure conservative chat-level invalidation before semantic expansion.


### 7 October — Human-reviewed cross-source plan connections

Phase7 foundation now supports local explicit same-plan identity over permitted current commitment facts. Original source IDs, quotes, state, truth and scope remain separate; no fuzzy matching, automatic conflict winner, Apple/project write or automatic group merge. Validated version lineage inherits identity. Bounded grouped recall and a same-selected-facts plan index reach PA/brief/suggestions under existing dependency guards. Group revisions set older advice aside when another connected member changes, including membership/correction/resolution/Forget; classification/review dates are excluded.

Focused fictional checks must cover equal-name cross-email/WhatsApp separation, proposed vs accepted vs reported cancellation/completion, exact same-chat version inheritance, source-off/missing/expiry, human correction/disconnection/Restore/Forget, same account/scope, forged group assignment, group-wide receipt invalidation, bounded recall/index and actual workspace item drilldown. A small real-subscription native-Mail state scenario is separate from deterministic storage checks and live UI acceptance; do not claim broad multi-turn identity accuracy. Continue with explicit foreground PA connections and canonical episode/native review bindings only after these checks.


### 7 October — Autonomous date proposals, durable review and reliability

User prioritises autonomous source-to-plan reasoning with human approval and a dedicated output inbox. Phase7 now includes inferred existing-native date-change proposals from bounded exact Mail/WhatsApp evidence, independent of manual memory-group connection. Background outputs persist in Review inbox without new general-chat delivery. Phase8 shows original/proposed dates, inferred match and quoted source, with fresh native review/Save and durable uncertain-save handling. There is no daily useful-output cap; independent inference budgets remain.

Required focused acceptance: clear distinctive deadline match, ambiguous duplicate abstention, hypothetical/negated abstention, strict date/time parsing, current source/native/timezone/permission gates, pending/approved persistence, quiet-result progress, capped-result pending survival, no chat replay and native claim-hop outside-edit refusal/readback/cleanup. Results belong in STATUS. Next acceptance: sustained wake/interval/day/allowance/outage/interruption behavior and useful/noisy proposal quality across source timelines. Memory episode identity, semantic consolidation, cross-source conflict decisions and richer delegated artifacts remain distinct work; date proposals do not claim them complete.
