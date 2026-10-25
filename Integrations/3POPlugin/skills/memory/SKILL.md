---
name: memory
description: Inspect or change facts, preferences and commitments stored in 3PO memory. Use for remember, correct, forget, resolve and reopen requests about 3PO's shared knowledge, not the host application's separate memory.
---

# Work with shared memory

Follow the [3PO operating contract](../../references/3po-contract.md).

Read the relevant topic/project guidance and matching memory before changing an existing fact. Use read_memory for targeted recall, read_memory_records for current/inactive records and read_life_notebook when typed supporting context is needed.

A human request to remember a fact authorises that memory save when the scope is clear. Use save_memory with a concise supported fact/preference/commitment and the human's actual words from the current conversation as evidence. Do not invent a quote or convert imported source content into a human statement.

For correct, forget, resolve or reopen, use the exact record issued by a relevant read and change_memory. Clarify materially different matches. Corrections preserve history; passing dates or missing source items do not resolve a commitment.

Distinguish a request to discuss a fact from one to persist it. Do not automatically save every utterance, an entire chat or speculative conclusions. Do not substitute a host-specific memory file for 3PO's canonical memory.

Require a verified saved outcome and read the relevant record again when needed to demonstrate the correction or removal. Explain what was stored, changed or forgotten, and avoid claiming that one memory operation erased separate notes, source messages or past conversations.
