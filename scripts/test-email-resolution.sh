#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcrun swiftc -module-cache-path /tmp/missioncontrol-test-modules MissionControl/Models.swift MissionControl/Mail/MailService.swift MissionControl/Mail/MailBatching.swift MissionControl/MemoryDependencies.swift MissionControl/EmailSummary.swift MissionControl/EmailResolution.swift Tests/EmailResolutionChecks.swift -o /tmp/missioncontrol-email-resolution-checks
/tmp/missioncontrol-email-resolution-checks
