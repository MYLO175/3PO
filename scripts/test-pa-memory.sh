#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcrun swiftc -module-cache-path /tmp/missioncontrol-test-modules MissionControl/PAMemory.swift Tests/PAMemoryChecks.swift -o /tmp/missioncontrol-pa-memory-checks
/tmp/missioncontrol-pa-memory-checks
