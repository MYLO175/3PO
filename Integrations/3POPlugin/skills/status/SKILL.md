---
name: status
description: Diagnose a 3PO connection, missing tools or source access, or check the outcome of a saved operation. Use for troubleshooting and uncertain saves, not as an automatic scan before every request.
---

# Check 3PO

Follow the [3PO operating contract](../../references/3po-contract.md).

For an interrupted change, start with action_status using its original requestID. Do not submit the mutation again with a new ID. If needed, read the exact original target to distinguish the current record from the historical receipt.

For connection trouble, call about_3po and use the returned capabilities and permissions. Separate app unavailable, bridge disabled, source context disabled, missing native permission, missing plugin tools and exhausted/changed connection scope. Do not infer the diagnosis from one generic transport error.

Use refresh_connection for a supported session-limit or source/account scope change, then read fresh target identities. It is not a host plugin-catalog reload and does not reset durable action receipts.

Keep troubleshooting read-only apart from that connection refresh. Do not change source exclusions, host approval settings or credentials, or restart Claude/Codex without a request covering that step. Never display the discovery file or token.

If the execution surface cannot reach the Mac app, describe that boundary instead of claiming the plugin is connected because its skills loaded.

Return what was confirmed, what remains uncertain and the smallest relevant next step. Do not claim a save from pending or an unavailable result.
