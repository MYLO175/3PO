#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/test-env.sh
missioncontrol_test_init review-conversation-trial
xcrun swiftc -D DEBUG -parse-as-library -module-cache-path "$MISSIONCONTROL_TEST_MODULE_CACHE" \
  MissionControl/ReviewConversationTrial.swift MissionControl/EvaluationLaunchGuard.swift \
  Tests/ReviewConversationTrialChecks.swift -o "$MISSIONCONTROL_TEST_BIN"
"$MISSIONCONTROL_TEST_BIN"
