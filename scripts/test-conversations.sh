#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/test-env.sh
missioncontrol_test_init conversations
xcrun swiftc -module-cache-path "$MISSIONCONTROL_TEST_MODULE_CACHE" MissionControl/Conversations.swift MissionControl/AssistantTranscriptProjection.swift MissionControl/PAMemory.swift MissionControl/LifeNotebook.swift Tests/ConversationChecks.swift Tests/AssistantTranscriptProjectionChecks.swift -o "$MISSIONCONTROL_TEST_BIN"
"$MISSIONCONTROL_TEST_BIN"
