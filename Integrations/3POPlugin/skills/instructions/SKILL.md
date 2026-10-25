---
name: instructions
description: Read or change 3PO Assistant, Projects, Reminders, Brief, Review, calendar-purpose and scoped project/topic guidance. Use for 3PO behaviour preferences, not host app settings, credentials or tool-permission policies.
---

# Work with instructions

Follow the [3PO operating contract](../../references/3po-contract.md).

Identify the feature or scope the human means. Use read_instructions with a null target for its directory when needed. Calendar targets come from current calendar reads; space targets come from current project reads. Read the exact owner and revision before editing.

Read both explicit text and separately returned learned guidance. An apparently empty explicit policy does not prove that no learned rule applies. Parent guidance applies to descendants, and a child's explicit guidance refines its scope.

For a clear requested policy change, preserve unrelated existing guidance, update the exact target with change_instructions and its revision, and verify the saved result. Do not replace the whole policy with a short new sentence if that would discard unrelated rules.

When the user means a learned rule, use its issued memory identity and change_memory to correct or forget it. Do not claim that editing explicit text deleted the learned record.

Explain the resulting behaviour and its scope. Stored instructions never grant source access or unrelated write permission. Do not change host approvals or macOS source permissions as a side effect.
