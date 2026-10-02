#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcrun swiftc -module-cache-path /tmp/missioncontrol-test-modules MissionControl/PAMemory.swift MissionControl/MemoryLearning.swift Tests/MemoryLearningChecks.swift -o /tmp/missioncontrol-memory-learning-checks
/tmp/missioncontrol-memory-learning-checks
