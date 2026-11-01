#!/bin/zsh
# Open a source-free DEBUG preview beside the installed 3PO without touching it.
# The copy gets its own name and bundle ID, so it never shares the installed
# app's preferences, single-copy check or window, and only the preview flag runs.
#
#   scripts/preview.sh [--no-build] --preview-calendar-scroll
#   scripts/preview.sh --preview-widget-sizes --sample   (later flags pass through)
#
# Builds Debug into a reusable root (MISSIONCONTROL_PREVIEW_ROOT, default
# /private/tmp/3po-preview) unless --no-build, then launches "3PO Preview".
set -euo pipefail
cd "$(dirname "$0")/.."

build=1; flag=""; extra=()
while (( $# )); do
  case "$1" in
    --no-build) build=0 ;;
    --preview-*) [[ -z "$flag" ]] || { print -u2 -- "Pass one preview flag."; exit 64; }; flag="$1" ;;
    --*) [[ -n "$flag" ]] || { print -u2 -- "Put the preview flag before $1."; exit 64; }; extra+=("$1") ;;
    *) print -u2 -- "Unknown option $1 (previews use --preview-* flags)"; exit 64 ;;
  esac
  shift
done
[[ -n "$flag" ]] || { print -u2 -- "Pass a preview flag, for example --preview-calendar-scroll."; exit 64; }

root="${MISSIONCONTROL_PREVIEW_ROOT:-/private/tmp/3po-preview}"
mkdir -p "$root"
if (( build )); then MISSIONCONTROL_BUILD_ROOT="$root" scripts/build.sh >/dev/null || { print -u2 -- "Build failed: $root/build.log"; exit 1; }; fi
product="$root/derived-data/Build/Products/Debug/3PO.app"
[[ -d "$product" ]] || { print -u2 -- "No Debug build at $product"; exit 1; }

app="$root/3PO Preview.app"
pkill -f "$app/Contents/MacOS/" 2>/dev/null || true
rm -rf "$app"; cp -R "$product" "$app"
plist="$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.mylomichael.missioncontrol.preview" -c "Set :CFBundleName 3PO Preview" "$plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName 3PO Preview" "$plist" 2>/dev/null || /usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string 3PO Preview" "$plist"
codesign --force --deep -s - "$app" 2>/dev/null
open -n "$app" --args "$flag" "${extra[@]}"
print -- "Opened 3PO Preview ($flag${extra:+ ${extra[*]}}) from $app"
