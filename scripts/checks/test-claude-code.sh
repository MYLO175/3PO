#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/lib/test-env.sh
missioncontrol_test_init claude-code
xcrun swiftc -module-cache-path "$MISSIONCONTROL_TEST_MODULE_CACHE" MissionControl/Infrastructure/Usage/AIUsage.swift MissionControl/Assistant/Provider/ChatGPTStream.swift MissionControl/Assistant/Provider/PAInferenceConnection.swift MissionControl/Assistant/Provider/PAInferenceRouter.swift MissionControl/Assistant/Provider/ClaudeCodeTranscript.swift MissionControl/Assistant/Provider/ClaudeCodeStream.swift MissionControl/Assistant/Provider/ClaudeCodeProcess.swift Tests/Assistant/ClaudeCodeChecks.swift -o "$MISSIONCONTROL_TEST_BIN"
"$MISSIONCONTROL_TEST_BIN" "$MISSIONCONTROL_TEST_WORK_DIR"
