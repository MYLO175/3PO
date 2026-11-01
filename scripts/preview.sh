#!/bin/zsh
# Open a source-free DEBUG preview beside the installed 3PO without touching it.
# The copy gets its own name and bundle ID, so it never shares the installed
# app's preferences, single-copy check or window, and only the preview flag runs.
#
#   scripts/preview.sh [--no-build] --preview-calendar-scroll
#   scripts/preview.sh --preview-widget-sizes --sample   (later flags pass through)
#   scripts/preview.sh --list                            (every preview copy on this Mac)
#
# Each copy is named after its branch, "3PO Preview (widget-sizes)" for
# claude/widget-sizes, or after the branch and flag elsewhere ("main-design"),
# with a matching bundle ID, so the Dock, Command-Tab and Activity Monitor tell
# copies apart. MISSIONCONTROL_PREVIEW_NAME overrides the name. Debug builds go
# to /private/tmp/3po-preview/<name> (MISSIONCONTROL_PREVIEW_ROOT overrides), so
# branches never share a build. The copy records its branch, commit and flags.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ "${1:-}" == "--list" ]]; then
  found=0; procs="$(ps -axo command=)"
  for app in /private/tmp/*/"3PO Preview"*.app(N/) /private/tmp/3po-preview/*/"3PO Preview"*.app(N/); do
    found=1
    info="$app/Contents/Info.plist"
    name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$info" 2>/dev/null || print -- "${app:t:r}")"
    state="stopped"; [[ "$procs" == *"$app/Contents/MacOS/"* ]] && state="running"
    if branch="$(/usr/libexec/PlistBuddy -c 'Print :MissionControlPreviewBranch' "$info" 2>/dev/null)"; then
      commit="$(/usr/libexec/PlistBuddy -c 'Print :MissionControlPreviewCommit' "$info")"
      flags="$(/usr/libexec/PlistBuddy -c 'Print :MissionControlPreviewFlags' "$info")"
      origin="branch $branch at $commit · $flags"
    else origin="older copy, branch not recorded"; fi
    print -- "$name · $state · $origin · made $(stat -f '%Sm' -t '%d %b %H:%M' "$app")"
    print -- "    $app"
  done
  (( found )) || print -- "No preview copies under /private/tmp."
  exit 0
fi

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

branch="$(git branch --show-current 2>/dev/null || true)"; commit="$(git rev-parse --short HEAD)"
if [[ -n "${MISSIONCONTROL_PREVIEW_NAME:-}" ]]; then name="$MISSIONCONTROL_PREVIEW_NAME"
elif [[ "$branch" == claude/* ]]; then name="${branch#claude/}"
else name="${branch:-detached}-${flag#--preview-}"; fi
name="$(print -r -- "${name:l}" | tr -cs 'a-z0-9-' '-' | sed 's/^-*//;s/-*$//')"
[[ -n "$name" ]] || name="preview"

root="${MISSIONCONTROL_PREVIEW_ROOT:-/private/tmp/3po-preview/$name}"
mkdir -p "$root"
if (( build )); then MISSIONCONTROL_BUILD_ROOT="$root" scripts/build.sh >/dev/null || { print -u2 -- "Build failed: $root/build.log"; exit 1; }; fi
product="$root/derived-data/Build/Products/Debug/3PO.app"
[[ -d "$product" ]] || { print -u2 -- "No Debug build at $product"; exit 1; }

title="3PO Preview ($name)"
app="$root/$title.app"
pkill -f "$root/3PO Preview.*app/Contents/MacOS/" 2>/dev/null || true
rm -rf "$app" "$root/3PO Preview.app"; cp -R "$product" "$app"
plist="$app/Contents/Info.plist"
set_key() { /usr/libexec/PlistBuddy -c "Set :$1 $2" "$plist" 2>/dev/null || /usr/libexec/PlistBuddy -c "Add :$1 string $2" "$plist"; }
set_key CFBundleIdentifier "com.mylomichael.missioncontrol.preview.$name"
set_key CFBundleName "$title"
set_key CFBundleDisplayName "$title"
set_key MissionControlPreviewBranch "${branch:-detached}"
set_key MissionControlPreviewCommit "$commit"
set_key MissionControlPreviewFlags "$flag${extra:+ ${extra[*]}}"
codesign --force --deep -s - "$app" 2>/dev/null
open -n "$app" --args "$flag" "${extra[@]}"
print -- "Opened $title ($flag${extra:+ ${extra[*]}}, $commit) from $app"
