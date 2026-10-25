#!/bin/sh
set -eu

fail() {
  printf '%s\n' "$1" >&2
  exit 1
}

if [ "$(/usr/bin/uname -s)" != "Darwin" ]; then
  fail "3PO needs a connection to its macOS app. This runtime is not the Mac host; use a supported host connection."
fi

if [ -n "${THREEPO_APP_PATH:-}" ]; then
  app_path="$THREEPO_APP_PATH"
  [ -d "$app_path" ] || fail "The configured 3PO application was not found."
else
  app_path=""
  for candidate in "$HOME/Applications/3PO.app" "/Applications/3PO.app"; do
    if [ -d "$candidate" ]; then
      app_path="$candidate"
      break
    fi
  done
  [ -n "$app_path" ] || fail "Install and open 3PO, then enable Settings > External assistants."
fi

info="$app_path/Contents/Info.plist"
[ -f "$info" ] || fail "The selected application is not a 3PO app bundle."
bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info" 2>/dev/null) || fail "The selected application has no readable identity."
[ "$bundle_id" = "com.mylomichael.missioncontrol" ] || fail "The selected application is not 3PO."

adapter="$app_path/Contents/Resources/MCPBridge/run.sh"
[ -f "$adapter" ] || fail "Update 3PO: its external assistant bridge is missing."
exec /bin/zsh "$adapter"
