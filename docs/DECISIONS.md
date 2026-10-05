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
