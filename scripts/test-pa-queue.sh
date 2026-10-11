#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/test-env.sh
missioncontrol_test_init pa-queue
xcrun swiftc -module-cache-path "$MISSIONCONTROL_TEST_MODULE_CACHE" MissionControl/Cache.swift "${missioncontrol_storage_sources[@]}" MissionControl/Conversations.swift MissionControl/PAMemory.swift MissionControl/LifeNotebook.swift MissionControl/PARequestQueue.swift Tests/PAQueueChecks.swift -o "$MISSIONCONTROL_TEST_BIN"
"$MISSIONCONTROL_TEST_BIN"
