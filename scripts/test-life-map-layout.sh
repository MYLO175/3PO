#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcrun swiftc -module-cache-path /tmp/missioncontrol-test-modules MissionControl/LifeMapLayout.swift MissionControl/PAIdentity.swift Tests/LifeMapLayoutChecks.swift -o /tmp/missioncontrol-life-map-layout-checks
/tmp/missioncontrol-life-map-layout-checks
