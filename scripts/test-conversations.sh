#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcrun swiftc -module-cache-path /tmp/missioncontrol-test-modules MissionControl/Conversations.swift MissionControl/PAMemory.swift MissionControl/LifeNotebook.swift Tests/ConversationChecks.swift -o /tmp/missioncontrol-conversation-checks
/tmp/missioncontrol-conversation-checks
