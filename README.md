# Mission Control
A local native macOS dashboard for Apple Calendar, Reminders and Mail. Stage 1 has no AI or subscription connection.

## Run
Requires macOS 26+, Xcode and an Apple Development signing identity. The installed app is `~/Applications/Mission Control.app`. Open it and grant Calendar full access, Reminders access and Automation access to Apple Mail when macOS asks. Permissions belong to this app, not helper scripts.

## Build
```sh
./scripts/build.sh
./scripts/test.sh
open '/tmp/missioncontrol-derived/Build/Products/Debug/Mission Control.app'
```
The build uses `/Applications/Xcode.app/Contents/Developer` without changing global settings, and writes derived output under `/tmp` to avoid Finder metadata interfering with signing. `scripts/generate-project.py` regenerates the normal Xcode project from Swift/JS files; open `MissionControl.xcodeproj` for editing. Signing team is configured for this Mac's existing identity; change `DEVELOPMENT_TEAM` in the generator when building elsewhere.

## Behaviour
- Compact three-panel dashboard; narrower windows place Inbox below Calendar and Reminders.
- Selected-day/tomorrow agenda and seven-day overview, including all-day and overlapping events.
- Calendar bars use Apple Calendar source colours. Reminders default to their Apple lists, with To do first and an optional Due date grouping; identity-based completion with one-level Undo. Read-only lists cannot be edited.
- Dynamically discovered account inboxes, last 30 days, with mailbox filters. The reader starts with today and works backwards in calendar-day windows, fetching at most 20 headers per page. Each page and its stable ID cursor are saved together; partial results appear immediately. Coverage shows completed date windows per account (31 calendar dates can overlap a rolling 30-day interval). Timeouts pause automatic reads; Refresh resumes progress. Plain-text bodies load only for a preview. No attachments, outgoing mail or AI requests.
- Manual/launch/wake refresh, EventKit change observation, Mail polling every five minutes. Errors retain last successful cache and show stale/error state.
- Source filters persist. Caches are stored with SwiftData in `~/Library/Application Support/Mission Control`, excluded from Git. Preferences use the app's UserDefaults domain.
- Closing the window keeps the menu bar app alive. Open it again from the menu bar. Explicit Quit stops it. Settings offers launch at login through Apple's SMAppService.

## Development checks
`--sample` launches without Apple-app reads or writes. `--small-window` sets an 820×640 content window for layout review. `--validate-live` is a developer-only acceptance mode: it creates UUID-marked duplicate-title and recurring disposable reminders, exercises production completion/Undo, verifies occurrence identity, then removes only its own marked items. Do not use it against an account whose test writes you do not authorise.

See [PLAN.md](PLAN.md) for all stages and [STATUS.md](STATUS.md) for current validation and outstanding checks. Stage 2 and dictation are deferred until review. Normal refresh never calls an AI service.

Implementation references: [EventKit access](https://developer.apple.com/documentation/eventkit/accessing-the-event-store), [login at launch](https://developer.apple.com/documentation/servicemanagement/smappservice/mainapp). Mail scripting uses the installed Apple Mail scripting dictionary.

Current delivery is a signed **Stage 1 checkpoint**. Both Exchange and iCloud inboxes completed their 30-day import in the actual app, with saved progress and mailbox filters. Live unread-preserving helper preview and actual-app preview passed. See STATUS.md for remaining permission, Calendar agreement and lifecycle acceptance boundaries. AI summaries remain Stage 2; the intended email experience is an overview, with raw messages available for source inspection.
