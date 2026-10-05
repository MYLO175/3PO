#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcrun swiftc -module-cache-path /tmp/missioncontrol-test-modules MissionControl/Cache.swift MissionControl/PAMemory.swift MissionControl/LifeNotebook.swift MissionControl/LifeOrganisation.swift MissionControl/LifeWorkspace.swift MissionControl/LifeProjectPlacement.swift MissionControl/LifeWorkspaceQuery.swift MissionControl/LifeWorkspaceStore.swift Tests/LifeWorkspaceChecks.swift -o /tmp/missioncontrol-life-workspace-checks
/tmp/missioncontrol-life-workspace-checks
