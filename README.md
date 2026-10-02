# Mission Control
A local native macOS dashboard for Apple Calendar, Reminders and Mail. The dashboard remains local. Stage 2 has begun with an optional ChatGPT subscription connection check in Settings; personal-source AI is not enabled yet.

## Run
Requires macOS 26+, Xcode and an Apple Development signing identity. The installed app is `~/Applications/Mission Control.app`. Open it and grant Calendar full access, Reminders access and Automation access to Apple Mail when macOS asks. Permissions belong to this app, not helper scripts.

## Build
```sh
./scripts/build.sh
./scripts/test.sh
open '/tmp/missioncontrol-derived/Build/Products/Debug/Mission Control.app'
```
The build regenerates the macOS icon from `MissionControl/Resources/AppIcon.png` using the bundled icon script and macOS sips. The menu bar uses a matching monochrome template symbol.

The build uses `/Applications/Xcode.app/Contents/Developer` without changing global settings, and writes derived output under `/tmp` to avoid Finder metadata interfering with signing. `scripts/generate-project.py` regenerates the normal Xcode project from Swift/JS files; open `MissionControl.xcodeproj` for editing. Signing team is configured for this Mac's existing identity; change `DEVELOPMENT_TEAM` in the generator when building elsewhere.

## Behaviour
- Compact three-panel dashboard; narrower windows place Inbox below Calendar and Reminders.
- Selected-day/tomorrow agenda and seven-day overview, including all-day and overlapping events.
- Calendar bars use Apple Calendar source colours. Reminders default to their Apple lists, with To do first and an optional Due date grouping; identity-based completion with one-level Undo. Read-only lists cannot be edited.
- Dynamically discovered account inboxes, last 30 days, with mailbox filters. The reader starts with today and works backwards in calendar-day windows, fetching at most 20 headers per page. Each page and its stable ID cursor are saved together; partial results appear immediately. Coverage shows completed date windows per account (31 calendar dates can overlap a rolling 30-day interval). Timeouts pause automatic reads; Refresh resumes progress. Plain-text bodies load only for a preview. No attachments or outgoing mail; normal dashboard refresh makes no AI requests.
- Manual/launch/wake refresh, EventKit change observation, Mail polling every five minutes. Errors retain last successful cache and show stale/error state.
- Source filters persist. Caches are stored with SwiftData in `~/Library/Application Support/Mission Control`, excluded from Git. Preferences use the app's UserDefaults domain.
- Closing the window keeps the menu bar app alive. Open it again from the menu bar. Explicit Quit stops it. Settings offers launch at login through Apple's SMAppService.

## Development checks
`--sample` launches without Apple-app reads or writes. `--small-window` sets an 820×640 content window for layout review. `--dark-window` tests dark appearance in the dashboard without changing the system theme. Debug builds offer Help → Run disposable Calendar check, which creates and cleans UUID-marked timed/all-day/overnight/recurring and UTC DST fixtures. `--validate-live` is a developer-only acceptance mode: it creates UUID-marked duplicate-title and recurring disposable reminders, exercises production completion/Undo, verifies occurrence identity, then removes only its own marked items. Do not use it against an account whose test writes you do not authorise.

See [PLAN.md](PLAN.md) for all stages and [STATUS.md](STATUS.md) for current validation and outstanding checks. Stage 2 is authorised and starts with a completed subscription inference check. Dictation follows later. Normal refresh never calls an AI service.

Implementation references: [EventKit access](https://developer.apple.com/documentation/eventkit/accessing-the-event-store), [login at launch](https://developer.apple.com/documentation/servicemanagement/smappservice/mainapp). Mail scripting uses the installed Apple Mail scripting dictionary.

Stage 1 has been reviewed; the current signed delivery also includes the initial Stage 2 assistant. Both Exchange and iCloud inboxes completed their 30-day import in the actual app, with saved progress and mailbox filters. Live unread-preserving helper preview and actual-app preview passed. Independent app permissions, Calendar agreement/live edge cases, compact light/dark layout, window close/menu-bar reopen and login registration have passed. Login registration was restored to off; actual startup after a new login has not been exercised. See STATUS.md for the validation record and boundaries. AI summaries remain Stage 2; the intended email experience is an overview, with raw messages available for source inspection.


## ChatGPT subscription checkpoint
Open Settings → Continue with ChatGPT. Complete the browser registration and grant ChatGPT plan usage, keeping credits disabled in app limits. The app validates the signed ID token, stores each account registration and credentials in macOS Keychain, discovers that account's models and sends a short source-free test using GPT-6.1 Sol Medium when available. It reports success only after a nonempty stream reaches `response.completed`; sign-in/model discovery alone is insufficient. Cancel, saved-account selection, renewal, sign-out and Usage controls are available. No API key or separately billed fallback is provided. The user authorised GPT-5.6 Sol Medium because GPT-6.1 Sol is absent from this account’s catalog. Completed subscription inference passed in the signed app.

`./scripts/test-auth.sh` checks RFC PKCE, callback state/path/duplicates, escaping, RSA signature verification and invalid identity rejection. Live eligibility and completed inference passed. Explicit live renewal passed and stored credentials in Keychain. A later request was rejected with the subscription usage-limit path; no automatic retry or billing fallback occurred. Official references: [registration](https://developers.openai.com/siwc/token-sharing-open-source/sign-in), [inference](https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference), [sessions](https://developers.openai.com/siwc/token-sharing-open-source/profiles-and-sessions).

## Initial assistant
Click Assistant in the dashboard to open or collapse streaming chat. Conversations are saved locally, separated by ChatGPT registration. Stop preserves partial output without treating it as complete. Settings includes editable preferences and independent AI calendar/list/account exclusions. Source context defaults off; when enabled, messages send bounded calendar/reminder snapshots and the latest 20 email headers through your ChatGPT plan. Headers do not imply body coverage. The assistant remains read-only. Bounded email summaries and briefing infrastructure are implemented below; live AI acceptance and requested calendar/reminder actions remain pending.

`./scripts/test-stream.sh` checks response deltas, completion and failed/incomplete/interrupted streams.

## Email overview checkpoint
The email panel now defaults to an overview; Sources opens the existing mailbox-filtered headers and previews. Settings → Automatic email summaries explains plain-text body transmission through your ChatGPT plan and enables independent processing. It defaults off. Each five-minute worker pass processes up to three eligible messages, newest first, and saves each successful summary. Errors pause processing until explicit Resume. Header fingerprints reuse unchanged summaries; body-only changes are checked in bounded batches using hashes, rotating through records older than 24 hours. Large backlogs can make rechecks take longer than a day; unchanged bodies do not trigger inference. Coverage is relative to loaded headers and separately shows Mail import coverage. Summaries are separated by ChatGPT registration and respect AI account exclusions. Needs-attention cards require a verbatim quote present in the supplied body/subject and link to the actual message preview. This validation does not prove every model claim is accurate. Live summary quality/backlog acceptance is pending subscription availability. The 07:30 briefing is described below.

`./scripts/test-summaries.sh` checks evidence validation, malformed output, persistence encoding and header invalidation using fictional messages.

## Morning briefing checkpoint
Settings offers an opt-in 7:30 daily briefing and notification permission. The app checks once a minute while running and at launch/wake, catching up if that day was missed. It reads enabled calendar/reminder context and reuses saved email summaries, with bounded input and partial coverage. Completed briefings persist locally per account/day; notification claims persist before scheduling, preventing automatic duplicate attempts. A crash or delivery failure after the claim can miss a notification. The Mac must be awake with the app running; this does not wake a sleeping Mac.

Usage-limit errors pause all assistant requests across relaunch. After access becomes available, Settings → Test connection makes one explicit source-free attempt. No automatic retries, credits or API billing fallback. An earlier request returned `subscription_sharing_usage_limit_exceeded` despite a saved 100% app cap and remaining plan allowance. A single connection test passed after the next normal reset; the earlier cause remains unresolved. Automatic summaries are now enabled and the production worker has saved real summaries. Daily briefing remains off pending live acceptance.

`./scripts/test-briefing.sh` checks the 7:30 threshold, DST/calendar dates, missed-run catch-up, persisted daily completion/notification claims and allowed source identities. Debug Settings includes a source-free test notification. Real AI briefing generation and overnight wake/notification acceptance remain pending.

Email model/reasoning settings are independent of interactive chat. Defaults retain the approved assistant model at Medium; choose an available Luna model at High if desired. Saved briefings can be selected by date. Summary caches expire outside the 30-day scope. Live source accuracy, source-link actions and briefing/banner validation remain distinct from successful generation/storage; see STATUS.md.
