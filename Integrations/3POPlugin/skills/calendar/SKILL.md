---
name: calendar
description: Read availability or create, move, edit and delete Apple Calendar events through 3PO. Use for actual appointments and calendar changes; use day or week for broader work planning.
---

# Work with Calendar

Follow the [3PO operating contract](../../references/3po-contract.md).

Resolve the requested date/range and timezone. Read current Calendar sources and events. Read applicable calendar-purpose guidance before choosing a destination. A proposed time needs actual availability coverage; an excluded or failed source is unknown.

For an existing event, use the exact occurrence issued by read_calendar and read_item_details before change_calendar. Read notes, location and recurrence so unrequested properties survive. For a create, choose a permitted writable destination from current sources and instructions.

For repeating events, establish the occurrence/series scope supported by the tool. Clarify a materially ambiguous event, date, timezone or repeat scope; do not add a second confirmation to an otherwise clear authorised change.

Use the current change_calendar schema and a fresh request UUID. Never substitute a native reminder or local project deadline for an event unless the request calls for that separate operation.

After a mutation, require a completed verified result and inspect the relevant item/range when needed to demonstrate the requested change. Report the event, resulting time/date and destination. For interruption, use action_status with the original UUID and stop if the result is uncertain.
