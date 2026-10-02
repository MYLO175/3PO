#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcrun swiftc -module-cache-path /tmp/missioncontrol-test-modules MissionControl/ChatGPTOAuth.swift Tests/ChatGPTAuthChecks.swift -o /tmp/missioncontrol-auth-checks
/tmp/missioncontrol-auth-checks
