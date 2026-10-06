#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcrun swiftc -module-cache-path /tmp/missioncontrol-test-modules MissionControl/Cache.swift MissionControl/AIUsage.swift MissionControl/AIUsageStore.swift Tests/AIUsageChecks.swift -o /tmp/missioncontrol-ai-usage-checks
/tmp/missioncontrol-ai-usage-checks
