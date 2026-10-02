#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcrun swiftc -module-cache-path /tmp/missioncontrol-test-modules MissionControl/Models.swift MissionControl/Mail/MailService.swift MissionControl/Mail/MailBatching.swift MissionControl/EmailSummary.swift MissionControl/Briefing.swift Tests/BriefingChecks.swift -o /tmp/missioncontrol-briefing-checks
/tmp/missioncontrol-briefing-checks
