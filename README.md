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
- Incomplete reminders grouped by due date; identity-based completion with one-level Undo. Read-only lists cannot be edited.
- Dynamically discovered enabled Mail account inboxes, last 30 days. Header reads and plain-text previews run through a serial subprocess; no attachments or outgoing mail.
- Manual/launch/wake refresh, EventKit change observation, Mail polling every five minutes. Errors retain last successful cache and show stale/error state.
- Source filters persist. Caches are stored with SwiftData in `~/Library/Application Support/Mission Control`, excluded from Git. Preferences use the app's UserDefaults domain.
- Closing the window keeps the menu bar app alive. Open it again from the menu bar. Explicit Quit stops it. Settings offers launch at login through Apple's SMAppService.

## Development checks
`--sample` launches without Apple-app reads or writes. `--small-window` sets an 820×640 content window for layout review. `--validate-live` is a developer-only acceptance mode: it creates UUID-marked duplicate-title and recurring disposable reminders, exercises production completion/Undo, verifies occurrence identity, then removes only its own marked items. Do not use it against an account whose test writes you do not authorise.

See [PLAN.md](PLAN.md) for all stages and [STATUS.md](STATUS.md) for current validation and outstanding checks. Stage 2 and dictation are deferred until review. Normal refresh never calls an AI service.

Implementation references: [EventKit access](https://developer.apple.com/documentation/eventkit/accessing-the-event-store), [login at launch](https://developer.apple.com/documentation/servicemanagement/smappservice/mainapp). Mail scripting uses the installed Apple Mail scripting dictionary.
