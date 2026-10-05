#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcrun swiftc -module-cache-path /tmp/missioncontrol-test-modules MissionControl/Models.swift MissionControl/ActionModels.swift MissionControl/ChatGPTStream.swift MissionControl/PAToolProtocol.swift MissionControl/LifeWorkspace.swift MissionControl/LifeProjectPlacement.swift MissionControl/LifeWorkspaceQuery.swift MissionControl/LifeWorkspaceToolSchema.swift MissionControl/PAMemory.swift MissionControl/LifeNotebook.swift MissionControl/LifeOrganisation.swift MissionControl/Conversations.swift MissionControl/PAProfileSetup.swift Tests/PAProfileSetupChecks.swift -o /tmp/missioncontrol-profile-checks
/tmp/missioncontrol-profile-checks
