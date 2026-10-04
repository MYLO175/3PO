#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcrun swiftc -module-cache-path /tmp/missioncontrol-test-modules MissionControl/Cache.swift MissionControl/Conversations.swift MissionControl/PAMemory.swift MissionControl/LifeNotebook.swift MissionControl/PARequestQueue.swift Tests/PAQueueChecks.swift -o /tmp/missioncontrol-pa-queue-checks
/tmp/missioncontrol-pa-queue-checks
