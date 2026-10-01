# Status
Stage 1 in progress. Empty folder inspected. Xcode 27.0 / Apple Development identity available. Initial five-hour remaining: 66%; weekly remaining: 53%. Main UI setting cannot be changed by prompt.
No personal source data in repository. One Luna High task assigned: Mail reader/service only.

## Integrated first build
- Xcode build succeeded using `/tmp/missioncontrol-derived` (workspace build output acquired Finder metadata and prevented signing).
- `./scripts/build.sh`: macOS 26 minimum, Swift 5 language mode, Xcode 27, team 4NYCBX3QPX, Apple Development identity, hardened runtime + Apple Events entitlement. Native unsandboxed local app.
- Implemented SwiftUI panels, EventKit identity-based reads/verified completion/Undo, SwiftData snapshots, filters, refresh/wake/change/polling, per-source stale/errors, menu bar lifecycle, SMAppService login toggle, serial JXA Mail reader.
- Subagent delivered Mail JS/service; main reviewed/fixed handler, dynamic inbox lookup, cache date coding and timeout requirements.
- 57% five-hour remaining at integrated build milestone. No resets/billing.
- Live permissions, source agreement, unread preservation and disposable reminder checks pending. No acceptance claim yet.

## Focused validation checkpoint
- Actual signed sample app launched and visually reviewed; real app installed at `/Users/mylomichael/Applications/Mission Control.app`.
- `./scripts/test.sh` passed: London 23/25-hour DST days, overnight overlap, all-day end exclusion, zero-duration events, recurring occurrence IDs, reminder due groups/order/duplicate IDs, Mail date/unread/flagged cache round-trip, helper timeout.
- Actual app Reminders permission/read verified. Duplicate-title disposable completion+Undo passed. A first recurring check exposed EventKit advancing the original series and creating a detached completed occurrence. Production code now tracks original and detached IDs, restores due date and removes the known detached completion atomically for Undo; live recheck in progress.
- Calendar permission was denied, with independent Reminders still usable. User asked to enable full Calendar access. No calendar agreement claim yet.
- Mail was unresponsive independently of dashboard; metadata scripts and native UI access timed out. User force-quit/reopened Mail. Retrying.
- Earlier expired read helpers were explicitly stopped. Current service uses hard-kill fallback after timeout.
- Usage milestone: 44% five-hour remaining. No resets or billing.

## Reminder recurrence validated
Actual signed app now passed disposable duplicate-title and daily-recurring completion+Undo, verifying exactly one restored recurring item and no detached completed duplicate; all UUID-marked test records cleaned up.
Mail stack sampling showed an expensive mailbox message database scan (not a dashboard UI hang). Corrected Inbox resolution to exact per-account Inbox name instead of aggregate Inbox child lookup. Earlier reader could select a broad mailbox. Old app stopped before retry; user asked to restart Mail after its stuck read and enable Calendar.
Latest exact-inbox-lookup build succeeded. Developer sample providers were separated from presentation. Testing 820×640 sample layout while waiting for Mail restart/Calendar permission. Failed write paths now refresh reminders to reconcile potentially applied but unverifiable saves.

## Reserve handoff (2026-10-01, Europe/London)
Five-hour allowance reached 17% remaining (83% used); stop after this small checkpoint per user reserve policy. No resets, credits or AI stages used.
Calendar permission fixed: hardened-runtime app requires `com.apple.security.personal-information.calendars`, which was missing. Added entitlement and legacy calendar description alongside full-access description. App then requested access and loaded 10 calendars, 9 events in seven days, across iCloud, Exchange, Other and Subscribed Calendars; successful cache verified in Application Support. Native dashboard displayed timed Exchange and iCloud events. Full independent agreement with Calendar app remains unverified.
Exact per-account Inbox probe passed in 0.15s for Exchange Inbox and iCloud INBOX. Complete header query still exceeds 45s and causes expensive Mail database scanning, even with correct inboxes. No successful app inbox/header/body coverage claim. Body/unread preservation implemented but live verification did not reach body retrieval.
Persisted Mail timeout suspension added: once a read times out, automatic launch/wake/poll reads remain paused until manual Refresh. Other sources keep working. This protects the Mac from repeated stalled scripting reads and retains stale Mail data if a successful cache exists.
Small window inspection exposed VSplit compressing Calendar agenda to almost nothing; narrow mode now uses a scrolling fixed arrangement with 440pt top panels and 360pt Inbox. Typical wide layout visually verified; narrow change compiled, final visual check pending.

### Next steps, in order
1. Use main GPT-6.1 Sol High temporarily for the unresolved Mail integration if user changes the chat setting; keep Standard speed. A prompt does not change model/reasoning/speed. One Luna High subagent already contributed JS/service; avoid another broad implementation or duplicate review.
2. Diagnose Mail reads with metadata-only step timing (no email content in logs). Avoid repeated broad `whose` queries, which appear to enumerate inbox messages through Mail's database. Investigate bounded indexed/range header reads and per-account subprocess timeouts/partial results; preserve honest 30-day coverage and cache reconciliation. No direct Mail database access or API billing was introduced.
3. Establish successful actual-app Exchange+iCloud headers, then preview an unread message and verify read status before/after. Open original in Mail and verify identity. Helper success alone is insufficient.
4. Independently compare native Calendar rows with Apple Calendar; sample automated date cases passed. Live all-day/overnight/recurrence fixtures not separately created for Calendar.
5. Verify filter/cache relaunch through UI, close-window/menu-bar reopen/Quit and launch-at-login toggle, and final narrow/light appearance checks. Cached Calendar/reminder snapshots already persisted and were restored during relaunch, but the full UI acceptance matrix is unfinished.
6. Rebuild/install final signed app and commit validation update. Do not start Stage 2 until Stage 1 completed and user reviewed.

### Reproducible commands
`./scripts/build.sh` (may require execution outside Codex sandbox for SwiftData macros/signing). Derived app `/tmp/missioncontrol-derived/Build/Products/Debug/Mission Control.app`.
`./scripts/test.sh` passes focused fixtures incl read-only sample write rejection. It uses `/tmp/missioncontrol-test-modules` to avoid sandbox cache restrictions.
Install using `ditto` to `~/Applications/Mission Control.app`, clear output bundle Finder xattrs with `xattr -cr`, verify `codesign --verify --deep --strict`, and `open` exact app path (macOS has a different built-in app with the same name).
`open ~/Applications/Mission\ Control.app --args --validate-live` runs authorised UUID-marked disposable duplicate/recurring reminder checks and cleans them. Actual app passed both checks, including one restored recurrence/no detached duplicate.
No personal exports, screenshots, emails or credentials committed. Source/cache diagnostics logged only counts/accounts/errors or disposable metadata. Caches live outside repo.

Final reserve checkpoint build succeeded and signed bundle verified. Installed to `~/Applications/Mission Control.app`; launched normally with persisted `mailSuspended=true` so automatic Mail reads remain paused. Calendar/Reminders refresh independently. Manual Refresh clears suspension and attempts Mail once. This is an incomplete Stage 1 delivery for review/resumption, not acceptance-complete.
