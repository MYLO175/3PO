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


## Overnight continuation — 2026-10-02
The one-time scheduled turn began at 03:30 Europe/London. Usage was initially 98% remaining in the five-hour window. No resets, credits, AI services or additional agents were used.

### Work saved
- MailService now discovers accounts first and runs one serial helper per account, with an independent 45-second timeout. A successful account survives a different account's timeout. Timeout suspension persists even when the helper returns a partial result.
- Account metadata remains available for filters during partial failures. Reconciliation retains only failed accounts' cached messages, removes disappeared records from successful accounts, deduplicates identities and drops cached messages outside the rolling 30-day scope.
- Resolve mailbox and preview-message JXA specifiers explicitly before reading properties; unresolved indexed references repeatedly resolve the account/mailbox. Preview also verifies the expected internet message identifier before displaying a body.
- Dashboard date header now updates each minute, rather than remaining on the previous date after midnight.
- Focused checks pass, including new fixtures for per-account timeout isolation, successful-empty reconciliation, expired stale messages and mismatched preview identity. Existing date/reminder/cache/timeout checks still pass.
- `./scripts/build.sh` succeeded; installed signed checkpoint at `/Users/mylomichael/Applications/Mission Control.app`, `codesign --verify --deep --strict` passed. Launched through Launch Services with `mailSuspended=true`. This launch does not establish independent TCC permission ownership or visual acceptance.

### Live investigation and limits
Only timing/count metadata was printed; personal header/body data was captured transiently in helper pipes and was not saved to Git or diagnostic logs.
- Dynamic Inbox discovery initially worked. Inbox counts were approximately 5,758 Exchange and 30,865 iCloud messages. Bounded date ranges succeeded; full iCloud date read using a resolved mailbox completed in approximately two seconds and found approximately 722 recent messages. Counts are a transient diagnostic, not validated app coverage.
- Resolved single-message header reads completed, but collection/header operations remained expensive. A replacement date-scan/index-range experiment still timed out for each account and was removed from production. Current production date predicate remains unresolved; no successful complete header snapshot or unread-preserving body preview is claimed.
- A one-second Mail stack sample showed Foundation index selection calling `MFMailbox.messages` / `MFLibraryIMAPStore.copyOfAllMessagesWithOptions` repeatedly and scanning SQLite on Mail's main thread. Large JXA object-specifier ranges therefore multiply complete-mailbox reads. Killing a timed-out helper does not cancel Mail's already running Apple event.
- Mail subsequently consumed about 82% CPU and even metadata discovery timed out. Stop live probes until Mail is restarted; do not repeatedly retry the installed app's Refresh. Automatic Mail reads remain paused. Do not force-quit the user's Mail without coordinating possible drafts.
- The native UI attempt to quit Mission Control and launch it through Finder remained pending for about 5 hours 44 minutes, eventually returning `cgWindowNotFound`. This delayed the overnight run; it was not continuous development during that interval. The cause (lock/sleep/window availability/tool failure) was not established. Later shell work resumed at about 09:17 London. Prior Mission Control process had quit successfully, but menu-bar reopen and other visual acceptance were not completed.

### Required user action and next work
1. Restart Apple Mail when convenient, preserving any draft first. Leave automatic reads paused until the replacement strategy is prepared. Avoid another whole-inbox indexed-range query.
2. Quit Mission Control, then launch `~/Applications/Mission Control.app` directly in Finder and approve its own prompts. Settings previously showed only ChatGPT and node for Calendar: data loaded after a Codex launch does not prove Mission Control independently owns access. Calendar/Reminders reads work in that launch context, but own-permission acceptance remains open.
3. Next focused Mail attempt should compare bulk date/ID retrieval with resolved unique-ID message reads, or a bundled AppleScript helper using evaluated message references. Avoid range selectors that enumerate the entire mailbox once per index; test a small batch before scaling. High reasoning could help assess these Apple Events evaluation/performance tradeoffs if the user changes the main chat setting. The instruction does not change the selected setting.
4. Once both actual-app inboxes load, verify unread preservation and original-message opening. Complete Calendar agreement and live event edge cases, filters/relaunch, menu-bar lifecycle, login toggle and compact/light layout.

Final usage milestone: 87% five-hour remaining, 40% weekly remaining. Stage 1 is an incomplete signed checkpoint; Stages 2 and 3 remain deferred.
