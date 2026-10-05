#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcrun swiftc -module-cache-path /tmp/missioncontrol-test-modules MissionControl/Models.swift MissionControl/ActionModels.swift MissionControl/ChatGPTStream.swift MissionControl/PAToolProtocol.swift MissionControl/LifeWorkspace.swift MissionControl/LifeWorkspaceToolSchema.swift MissionControl/PAMemory.swift MissionControl/LifeNotebook.swift MissionControl/LifeOrganisation.swift Tests/PAToolChecks.swift -o /tmp/missioncontrol-pa-tool-checks
/tmp/missioncontrol-pa-tool-checks
