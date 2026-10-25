---
name: undo
description: Recover from a specific 3PO operation using its receipt, supported latest-operation undo, or restoration of an exact deleted Project record. Use for 3PO recovery, not general Git undo or arbitrary historical rollback.
---

# Recover a change

Follow the [3PO operating contract](../../references/3po-contract.md).

Establish which operation the human means, its store and its original requestID when available. Use action_status for an interrupted or uncertain operation before considering recovery, and read the relevant current target.

For a deleted local Project item, read Recently deleted, identify the exact requested record and use restore_life_item. Do not confuse native Reminder/Calendar deletion with local project deletion.

undo_apple_change applies only to the latest supported app edit/reminder completion and refuses subsequent outside changes; creation, deletion and series changes are outside its scope. undo_life_edit is a separate one-level, session-only local edit undo with exclusions for creation and relationships.

Do not invoke a global latest-operation tool when concurrent work leaves its ownership unknown. A receipt for an earlier change does not prove that change is still latest. Explain that limitation and resolve the target/scope or propose a specific inverse edit for the human to request.

An authorised inverse edit is a new operation with its own UUID and exact fresh target; it is not a retry of an uncertain original operation. Never attempt automatic multi-store rollback.

Confirm only a completed verified recovery, including what was restored or reversed. State unsupported cases plainly.
