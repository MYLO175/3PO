#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcrun swiftc -module-cache-path /tmp/missioncontrol-test-modules MissionControl/Cache.swift MissionControl/PAMemory.swift MissionControl/MemoryInspection.swift MissionControl/LifeNotebook.swift MissionControl/LifeOrganisation.swift MissionControl/MemoryLearning.swift MissionControl/PALearningQuestion.swift MissionControl/Briefing.swift MissionControl/LifeWorkspace.swift MissionControl/LifeProjectPlacement.swift MissionControl/LifeWorkspaceQuery.swift MissionControl/LifeWorkspaceStore.swift MissionControl/LifeCanonicalNotebook.swift MissionControl/PAMemoryStore.swift Tests/SecondBrainChecks.swift -o /tmp/missioncontrol-second-brain-checks
/tmp/missioncontrol-second-brain-checks
