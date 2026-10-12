#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/test-env.sh
missioncontrol_test_init conversation-repository
xcrun swiftc -module-cache-path "$MISSIONCONTROL_TEST_MODULE_CACHE" -swift-version 5 MissionControl/Cache.swift MissionControl/LocalRecordRepository.swift MissionControl/PAMemory.swift MissionControl/LifeNotebook.swift MissionControl/Conversations.swift MissionControl/ConversationRepository.swift Tests/ConversationRepositoryChecks.swift -o "$MISSIONCONTROL_TEST_BIN"
"$MISSIONCONTROL_TEST_BIN"
