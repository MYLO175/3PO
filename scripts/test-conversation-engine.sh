#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/test-env.sh
missioncontrol_test_init conversation-engine
xcrun swiftc -module-cache-path "$MISSIONCONTROL_TEST_MODULE_CACHE" -swift-version 5 MissionControl/Models.swift MissionControl/ActionModels.swift MissionControl/AIUsage.swift MissionControl/ChatGPTStream.swift MissionControl/PAToolProtocol.swift MissionControl/PAConversationEngine.swift MissionControl/LifeWorkspace.swift MissionControl/LifeProjectPlacement.swift MissionControl/LifeWorkspaceQuery.swift MissionControl/LifeWorkspaceToolSchema.swift MissionControl/PAMemory.swift MissionControl/LifeNotebook.swift MissionControl/LifeOrganisation.swift Tests/ConversationEngineChecks.swift -o "$MISSIONCONTROL_TEST_BIN"
"$MISSIONCONTROL_TEST_BIN"
