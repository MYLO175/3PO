#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcrun swiftc -module-cache-path /tmp/missioncontrol-test-modules MissionControl/Models.swift MissionControl/Mail/MailService.swift MissionControl/Mail/MailBatching.swift Tests/MailCancellationChecks.swift -o /tmp/missioncontrol-mail-cancellation-checks
/tmp/missioncontrol-mail-cancellation-checks
