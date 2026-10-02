#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcrun swiftc -module-cache-path /tmp/missioncontrol-test-modules -swift-version 5 MissionControl/Models.swift MissionControl/SampleServices.swift MissionControl/Mail/MailService.swift MissionControl/Mail/MailBatching.swift Tests/FocusedChecks.swift -o /tmp/missioncontrol-focused-checks
/tmp/missioncontrol-focused-checks
