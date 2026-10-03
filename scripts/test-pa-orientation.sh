#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcrun swiftc -module-cache-path /tmp/missioncontrol-test-modules MissionControl/Models.swift MissionControl/PAOrientation.swift Tests/PAOrientationChecks.swift -o /tmp/missioncontrol-pa-orientation-checks
/tmp/missioncontrol-pa-orientation-checks
