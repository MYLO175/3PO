#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcrun swiftc -module-cache-path /tmp/missioncontrol-test-modules MissionControl/PAMemory.swift MissionControl/MemoryLearning.swift MissionControl/PALearningQuestion.swift MissionControl/Briefing.swift Tests/PAMemoryChecks.swift -o /tmp/missioncontrol-pa-memory-checks
/tmp/missioncontrol-pa-memory-checks
