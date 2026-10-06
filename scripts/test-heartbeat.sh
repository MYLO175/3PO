#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcrun swiftc -module-cache-path /tmp/missioncontrol-test-modules MissionControl/Heartbeat.swift Tests/HeartbeatChecks.swift -o /tmp/missioncontrol-heartbeat-checks
/tmp/missioncontrol-heartbeat-checks
