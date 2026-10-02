#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcrun swiftc -module-cache-path /tmp/missioncontrol-test-modules MissionControl/Cache.swift MissionControl/PAMemory.swift MissionControl/MemoryLearning.swift MissionControl/PAMemoryStore.swift Tests/MemoryStoreChecks.swift -o /tmp/missioncontrol-memory-store-checks
/tmp/missioncontrol-memory-store-checks
