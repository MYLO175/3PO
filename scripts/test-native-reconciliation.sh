#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/test-env.sh
missioncontrol_test_init native-reconciliation
xcrun swiftc -module-cache-path "$MISSIONCONTROL_TEST_MODULE_CACHE" MissionControl/NativeReconciliation.swift Tests/NativeReconciliationChecks.swift -o "$MISSIONCONTROL_TEST_BIN"
"$MISSIONCONTROL_TEST_BIN"
