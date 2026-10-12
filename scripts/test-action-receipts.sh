#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/test-env.sh
missioncontrol_test_init action-receipts
xcrun swiftc -module-cache-path "$MISSIONCONTROL_TEST_MODULE_CACHE" -swift-version 5 MissionControl/Models.swift MissionControl/ActionModels.swift MissionControl/NativeCreation.swift MissionControl/NativeEditing.swift MissionControl/NativeActionRuntime.swift MissionControl/AIUsage.swift MissionControl/ChatGPTStream.swift MissionControl/PAToolProtocol.swift MissionControl/LifeWorkspace.swift MissionControl/LifeProjectPlacement.swift MissionControl/LifeWorkspaceQuery.swift MissionControl/LifeWorkspaceToolSchema.swift MissionControl/PAMemory.swift MissionControl/LifeNotebook.swift MissionControl/LifeOrganisation.swift MissionControl/Cache.swift MissionControl/LocalRecordRepository.swift MissionControl/ActionReceiptStore.swift MissionControl/AssistantActions.swift Tests/ActionReceiptChecks.swift -o "$MISSIONCONTROL_TEST_BIN"
"$MISSIONCONTROL_TEST_BIN"
