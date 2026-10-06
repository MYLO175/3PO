#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcrun swiftc -module-cache-path /tmp/missioncontrol-test-modules MissionControl/Cache.swift MissionControl/Conversations.swift MissionControl/PAMemory.swift MissionControl/LifeNotebook.swift MissionControl/ChatDraftStore.swift MissionControl/PARequestQueue.swift MissionControl/ChatImages.swift Tests/ChatImageChecks.swift -o /tmp/missioncontrol-image-checks
/tmp/missioncontrol-image-checks
