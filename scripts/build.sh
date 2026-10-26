#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
# Debug by default (evaluation tiers need a DEBUG candidate); --release builds
# the optimised app for everyday installation.
configuration=Debug
if [[ "${1:-}" == "--release" ]]; then configuration=Release; shift; fi
# Generated checkout resources still have one writer. Compiler artifacts/logs
# get a new root each invocation unless the integration owner supplies one.
MISSIONCONTROL_BUILD_ROOT="${MISSIONCONTROL_BUILD_ROOT:-$(mktemp -d "${TMPDIR:-/private/tmp}/missioncontrol-build.XXXXXX")}"
mkdir -p "$MISSIONCONTROL_BUILD_ROOT"
MISSIONCONTROL_BUILD_ROOT="$(cd "$MISSIONCONTROL_BUILD_ROOT" && pwd -P)"
MISSIONCONTROL_DERIVED_DATA="${MISSIONCONTROL_DERIVED_DATA:-$MISSIONCONTROL_BUILD_ROOT/derived-data}"
MISSIONCONTROL_BUILD_LOG="${MISSIONCONTROL_BUILD_LOG:-$MISSIONCONTROL_BUILD_ROOT/build.log}"
mkdir -p "$(dirname "$MISSIONCONTROL_BUILD_LOG")"
print -- "Build artifacts: $MISSIONCONTROL_BUILD_ROOT"
print -- "Build log: $MISSIONCONTROL_BUILD_LOG"
if [[ ! -d WhatsAppBridge/node_modules ]]; then
  npm --cache "$MISSIONCONTROL_BUILD_ROOT/npm-cache" ci --ignore-scripts --prefix WhatsAppBridge
fi
if [[ ! -d MCPBridge/node_modules ]]; then
  npm --cache "$MISSIONCONTROL_BUILD_ROOT/npm-cache" ci --ignore-scripts --prefix MCPBridge
fi
python3 scripts/packaging/patch-baileys-readonly.py
python3 scripts/packaging/package-whatsapp-runtime.py
python3 scripts/assets/build-icon.py
python3 scripts/project/generate-project.py
xcodebuild -project MissionControl.xcodeproj -scheme MissionControl -configuration "$configuration" -derivedDataPath "$MISSIONCONTROL_DERIVED_DATA" build "$@" 2>&1 | tee "$MISSIONCONTROL_BUILD_LOG"
python3 scripts/packaging/verify-app-bundle.py "$MISSIONCONTROL_DERIVED_DATA/Build/Products/$configuration/3PO.app"
