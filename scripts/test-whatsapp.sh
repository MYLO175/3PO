#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
python3 scripts/patch-baileys-readonly.py
xcrun swiftc -module-cache-path /tmp/missioncontrol-test-modules MissionControl/WhatsAppModels.swift Tests/WhatsAppChecks.swift -o /tmp/missioncontrol-whatsapp-checks
/tmp/missioncontrol-whatsapp-checks
WhatsAppBridge/Runtime/node --test WhatsAppBridge/*.test.mjs
node --check WhatsAppBridge/reader.mjs
