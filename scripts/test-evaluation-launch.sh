#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/test-env.sh
missioncontrol_test_init evaluation-launch
xcrun swiftc -module-cache-path "$MISSIONCONTROL_TEST_MODULE_CACHE" MissionControl/EvaluationLaunchGuard.swift Tests/EvaluationLaunchChecks.swift -o "$MISSIONCONTROL_TEST_BIN"
"$MISSIONCONTROL_TEST_BIN"
