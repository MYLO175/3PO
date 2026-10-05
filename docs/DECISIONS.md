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
