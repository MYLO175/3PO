#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcrun swiftc -module-cache-path /tmp/missioncontrol-test-modules MissionControl/Models.swift MissionControl/CalendarTimeline.swift Tests/CalendarTimelineChecks.swift -o /tmp/missioncontrol-calendar-timeline-checks
/tmp/missioncontrol-calendar-timeline-checks
