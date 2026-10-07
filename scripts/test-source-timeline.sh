#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcrun swiftc -module-cache-path /tmp/missioncontrol-test-modules MissionControl/Cache.swift MissionControl/PAMemory.swift MissionControl/LifeNotebook.swift MissionControl/LifeOrganisation.swift MissionControl/MemoryLearning.swift MissionControl/PALearningQuestion.swift MissionControl/MemoryDependencies.swift MissionControl/Briefing.swift MissionControl/WhatsAppModels.swift MissionControl/SourceContextLearning.swift MissionControl/PAMemoryStore.swift Tests/SourceTimelineChecks.swift -o /tmp/missioncontrol-source-timeline-checks
/tmp/missioncontrol-source-timeline-checks
