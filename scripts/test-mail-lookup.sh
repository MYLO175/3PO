#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcrun swiftc -module-cache-path /tmp/missioncontrol-test-modules MissionControl/Models.swift MissionControl/ActionModels.swift MissionControl/Mail/MailService.swift MissionControl/Mail/MailBatching.swift MissionControl/MailLookupRules.swift MissionControl/MailLookupCoverage.swift Tests/MailLookupChecks.swift -o /tmp/missioncontrol-mail-lookup-checks
/tmp/missioncontrol-mail-lookup-checks
