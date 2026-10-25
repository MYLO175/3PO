---
name: reminders
description: Read, create, edit, complete or delete Apple Reminders through 3PO, including lists, due dates and repeats. Use when the user means native Reminders; keep local Project tasks separate.
---

# Work with Reminders

Follow the [3PO operating contract](../../references/3po-contract.md).

Read Reminder instructions and current reminders/lists. Use the human's stated destination and date; otherwise use the normal destination supported by saved guidance. Ask only if the missing choice materially affects the result.

For an existing reminder, read its exact issued ID with read_item_details before change_reminder. Preserve notes, alerts, priority, URL and repetition unless the requested change covers them. Date-only, timed and undated reminders have different meanings.

A repeating reminder edit or deletion uses the actual reminderSeries scope and affects the native repeating reminder. Explain that scope when it matters to intent. Completing a reminder and deleting it are different operations.

For an authorised temporary write test, create a distinct undated test title, read back the newly issued item, delete only that exact item, and verify it is gone. Never delete an older reminder just because its title matches.

Require completed with verified:true for saved outcomes. Keep the original request UUID through an interruption. Report the concrete result and any unresolved partial operation; do not claim a local Project task was also completed.
