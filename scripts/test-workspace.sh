#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcrun swiftc -module-cache-path /tmp/missioncontrol-test-modules -swift-version 5 MissionControl/WorkspaceModels.swift Tests/WorkspaceChecks.swift -o /tmp/missioncontrol-workspace-checks
/tmp/missioncontrol-workspace-checks
