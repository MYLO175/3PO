# Next improvements

This is the product roadmap to review together. The detailed next-stage architecture is in [PA intelligence plan](PA_INTELLIGENCE_PLAN.md), approved scope in [PLAN](../PLAN.md), and exact validation boundaries in [STATUS](../STATUS.md). PA quality remains the priority; map layout, 3PO palettes and local PA naming have also been refined.

| Area | Already implemented | Next improvement | Success looks like |
| --- | --- | --- | --- |
| Topic focus | Separate transcripts, focus text, optional area preference, two-hop permitted recall | More specific entity anchors and measured semantic recall if needed | Engineering recalls modules/projects/career links while retaining important shared context |
| Linked notebook | One self identity, typed connections, area notes and pinned organisation | Reusable non-self entity identities, supported aliases and custom subareas | One coherent person/project identity rather than several slightly different names |
| Source learning | Foreground source tools plus separate opt-in recent WhatsApp delta learning, scoped source evidence and shared learning quota | Mail/Calendar/Reminders deltas and source-aware persistent brief/suggestion dependencies | Useful supported context can be learned without requiring a chat, with its origin visible |
| Refinement | Versioned human corrections/restore, earlier-evidence protection, exact duplicate avoidance and provisional review expiry | Reviewable semantic consolidation, conflicts, alias proposals and temporary-context archiving | Less repetition, no silent loss of confirmed facts, corrections persist |
| Helpful questions | Dedicated small-question setup uses notebook breadth; optional grounded daily question | Evaluate multi-turn coverage, skip behaviour and useful source-driven uncertainty | Few useful questions, no repetitive onboarding or routine approval requests |
| Life map | Searchable Map/Notes widget, coloured area hubs, typed facts and evidence inspection | Validate real-profile interaction, then entity expansion/cross-link navigation | A readable explanation of the PA's beliefs, not a ball of decorative lines |
| Background handoffs | Queue and completed outputs, local email drafts | Better progress, source references, editable outputs and resumption controls | You can delegate several tasks and review their results later |
| Reliability | Bounded tools, ownership, deterministic notebook fixtures and a repeatable fictional subscription evaluator | Broader multi-turn/source/proactive evaluations plus live personal acceptance | Correct recall/actions, honest uncertainty and no duplicated changes |

## Topic focus design

A topic should be a focus lens over the connected notebook, not a second assistant with a separate view of your whole life. Keep separate ongoing transcripts, as requested. Store explicit graph anchors for the topic, then prioritise their notes and nearby connections. Shared critical context remains available. Focus is a retrieval preference, not a new permission grant or an excuse to expose another account/topic's private material.

The initial implementation now has an optional preferred area and connected-entity retrieval. More precise entity anchors and alias resolution remain future work; area focus alone does not prove perfect recall.

## Background learning and refinement

Use small source deltas with saved progress, rather than an inbox/history sweep. Capture source/account/topic ownership before inference. Attach evidence, freshness and confidence to beliefs. Human-confirmed facts take priority; disagreement should be exposed rather than silently overwritten.

Consolidation should preserve evidence and correction history. Prefer reversible changes or reviewable proposals for meaningful contradictions. Archive temporary context without assuming its real-world task was completed. Source access, learning and notification controls should remain understandable and independently controllable.

## Questions worth asking

Examples include how two similar project names relate, which recurring commitment matters most, or whether an apparent deadline is actually your responsibility. Ask only when the answer would change useful help. Avoid asking for facts already known or requesting secrets.

## Product questions to revisit

- Which areas deserve an explicit hub, and which should emerge from useful repeated context?
- Should a topic's graph anchors be picked manually, suggested by the PA, or both?
- How should a corrected belief show its old evidence without cluttering everyday use?
- Which suggestions deserve a notification rather than a quiet Tasks for you card?
- What examples should be in the repeatable evaluation set to establish that the PA is improving?
