#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/test-env.sh
missioncontrol_test_init life-relationship-tools
xcrun swiftc -module-cache-path "$MISSIONCONTROL_TEST_MODULE_CACHE" MissionControl/Cache.swift "${missioncontrol_storage_sources[@]}" MissionControl/Models.swift MissionControl/ActionModels.swift MissionControl/AIUsage.swift MissionControl/ChatGPTStream.swift MissionControl/WorkspaceModels.swift MissionControl/PAToolProtocol.swift MissionControl/PAMemory.swift MissionControl/LifeNotebook.swift MissionControl/LifeOrganisation.swift MissionControl/LifeWorkspace.swift MissionControl/LifeProjectPlacement.swift MissionControl/LifeWorkspaceQuery.swift MissionControl/LifeWorkspaceStore.swift MissionControl/LifeWorkspaceToolSchema.swift MissionControl/LifeWorkspaceTools.swift Tests/LifeRelationshipToolChecks.swift -o "$MISSIONCONTROL_TEST_BIN"
"$MISSIONCONTROL_TEST_BIN"
