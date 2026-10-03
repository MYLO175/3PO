#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcrun swiftc -module-cache-path /tmp/missioncontrol-test-modules MissionControl/Weather.swift Tests/WeatherChecks.swift -o /tmp/missioncontrol-weather-checks
/tmp/missioncontrol-weather-checks
