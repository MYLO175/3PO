# Heartbeat analysis and reliability

Approved direction, 13 October 2026. Implementation and acceptance are recorded separately in STATUS.

A heartbeat analyses already collected information in the context of the user's life. It prepares a current brief, reviews incoming information and proposes useful actions, learns supported life context, and places new memories into the existing organisation. It does not depend on every source successfully refreshing at that moment.

## Implementation plan

1. Keep Calendar/Reminders, Mail, WhatsApp and weather collection independent and free of AI. Heartbeat consumers use bounded cached snapshots with collection coverage and revision guards. A failed poll does not erase usable prior data; a known source change cannot authorise stale advice.
2. Give email review, memory/organisation, suggestions and briefing separate persisted outcomes. A recoverable analysis failure retains completed work and allows the brief to use remaining supported context. Account/permission changes, foreground work, sleep, Stop, usage suspension and exhausted whole-run limits still end the owned run. Failed stages wait for a fresh scheduled cycle, not an immediate replay.
3. Prepare suggestions through one completed strict typed result, matching the brief's approach. Validate evidence, dates, targets and ownership locally. Record safe section/row/field/reason diagnostics, without retaining model fragments or personal source text in failure logs. Reject an invalid comparison as a whole so a sibling handled/resolved association cannot hide its failed action.
4. The user confirmed that sources already allowed for review may also teach memory. Derive that permission from current review controls and exact enabled source scope; keep existing explicit choices and source evidence. New inherited scopes baseline old content rather than scanning history. Revoking source access withdraws dependent facts from recall. Failed learning claims retain their pause.
5. Run a bounded fair learning lane under heartbeat ownership, retaining shared learning budgets. Attach new facts to existing life areas in the learning pass; keep facts, correction lineage and human-pinned organisation authoritative. Never automatically create human projects or tasks.
6. Verify actual scheduler orchestration with fictional failures, cached-source availability, ownership interruption and successful cycles. Check the configured model's typed compound-email suggestions, signed application checks, installation preservation and one live cycle. Several days of reliable unattended use remain separate acceptance work.

Calendar entries and dated tasks in the existing IIB MEng Project remain separate reviewable suggestions, with approve and natural-language adjustment. The optional daily heartbeat limit defaults to Off and remains visible in Settings → Background.

The strict-result schema follows the required-fields, nullable optional values and closed-object rules in [official OpenAI function-calling guidance](https://developers.openai.com/api/docs/guides/function-calling). Local evidence validation remains separate.
