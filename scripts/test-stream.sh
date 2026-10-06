#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcrun swiftc -module-cache-path /tmp/missioncontrol-test-modules MissionControl/AIUsage.swift MissionControl/ChatGPTStream.swift MissionControl/ChatGPTRecovery.swift Tests/ChatGPTStreamChecks.swift -o /tmp/missioncontrol-stream-checks
/tmp/missioncontrol-stream-checks
