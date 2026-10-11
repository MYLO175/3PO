#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/test-env.sh
missioncontrol_test_init mail-lookup
xcrun swiftc -module-cache-path "$MISSIONCONTROL_TEST_MODULE_CACHE" MissionControl/Models.swift MissionControl/ActionModels.swift MissionControl/Mail/MailService.swift MissionControl/Mail/MailBatching.swift MissionControl/MailLookupRules.swift MissionControl/MailLookupCoverage.swift Tests/MailLookupChecks.swift -o "$MISSIONCONTROL_TEST_BIN"
"$MISSIONCONTROL_TEST_BIN"
