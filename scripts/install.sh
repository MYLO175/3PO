#!/bin/zsh
# Replace the installed 3PO with a built candidate: verify, quit, back up,
# swap atomically, verify again. Personal records are hashed before and after
# the swap (read-only) so the copy can never silently change them.
#
#   scripts/install.sh [--dry-run] [--launch] [--label NAME] [PATH/TO/3PO.app]
#
# The default candidate is the Release product of MISSIONCONTROL_BUILD_ROOT.
# --dry-run runs every check and prints the plan without quitting, backing up
# or copying anything.
set -euo pipefail
cd "$(dirname "$0")/.."

dry_run=0; launch=0; label=""; candidate=""
while (( $# )); do
  case "$1" in
    --dry-run) dry_run=1 ;;
    --launch) launch=1 ;;
    --label) shift; label="$1" ;;
    -*) print -u2 -- "Unknown option $1"; exit 64 ;;
    *) candidate="$1" ;;
  esac
  shift
done
if [[ -z "$candidate" ]]; then
  [[ -n "${MISSIONCONTROL_BUILD_ROOT:-}" ]] || { print -u2 -- "Pass the candidate 3PO.app or set MISSIONCONTROL_BUILD_ROOT."; exit 64; }
  candidate="$MISSIONCONTROL_BUILD_ROOT/derived-data/Build/Products/Release/3PO.app"
fi
candidate="${candidate:A}"
bundle_id=com.mylomichael.missioncontrol
installed="$HOME/Applications/3PO.app"
support="$HOME/Library/Application Support/Mission Control"
helper_support="$HOME/Library/Application Support/$bundle_id"
backups="$HOME/Library/Application Support/3PO Development Backups"
commit="$(git rev-parse --short HEAD)"
[[ -n "$label" ]] || label="$(git branch --show-current | sed 's|.*/||')"
backup="$backups/$(date +%Y%m%d-%H%M%S)-$label"

fail() { print -u2 -- "Install stopped: $1"; exit 1; }

# 1. The candidate must be a signed 3PO bundle.
[[ -d "$candidate" && "${candidate:t}" == "3PO.app" ]] || fail "no 3PO.app at $candidate"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$candidate/Contents/Info.plist")" == "$bundle_id" ]] || fail "candidate bundle ID differs"
codesign --verify --deep --strict "$candidate" || fail "candidate signature is invalid"
python3 scripts/packaging/verify-app-bundle.py "$candidate" >/dev/null || fail "candidate bundle is incomplete"
kind=Release; [[ -e "$candidate/Contents/MacOS/3PO.debug.dylib" ]] && kind=Debug

# 2. Only the installed copy may be running; never race another candidate.
running=("${(@f)$(pgrep -fl '/3PO.app/Contents/MacOS/3PO' 2>/dev/null || true)}")
for line in "${running[@]}"; do
  [[ -z "$line" ]] && continue
  [[ "$line" == *"$installed/Contents/MacOS/3PO"* ]] || fail "another 3PO copy is running: ${line#* }"
done

print -- "Candidate: $candidate ($kind, commit $commit)"
print -- "Installed: $installed"
print -- "Backup:    $backup"
if (( dry_run )); then print -- "Dry run: checks passed; nothing was quit, backed up or copied."; exit 0; fi

# 3. Quit the installed app normally and wait for it (and its helpers) to exit.
if pgrep -f "$installed/Contents/MacOS/3PO" >/dev/null; then
  osascript -e "tell application id \"$bundle_id\" to quit" >/dev/null 2>&1 || true
  for _ in {1..60}; do pgrep -f "$installed/Contents/MacOS/3PO" >/dev/null || break; sleep 1; done
  pgrep -f "$installed/Contents/MacOS/3PO" >/dev/null && fail "3PO did not quit within a minute; nothing was changed"
fi

# 4. Back up records, helper data, preferences and the current app, then verify the copy.
mkdir -p "$backup"
python3 scripts/packaging/record-digest.py "$support/Dashboard.store" > "$backup/before.json"
[[ -d "$support" ]] && ditto "$support" "$backup/application-support"
[[ -d "$helper_support" ]] && ditto "$helper_support" "$backup/helper-support"
defaults export "$bundle_id" "$backup/preferences.plist"
[[ -d "$installed" ]] && ditto "$installed" "$backup/previous-3PO.app"
[[ -d "$support" ]] && { diff -rq "$support" "$backup/application-support" >/dev/null || fail "record backup differs from the original; nothing was replaced"; }

# 5. Stage beside the destination and swap.
staging="$HOME/Applications/.3PO-staging.app"
rm -rf "$staging"
ditto "$candidate" "$staging"
codesign --verify --deep --strict "$staging" || fail "staged copy signature is invalid; the installed app is unchanged"
[[ -d "$installed" ]] && mv "$installed" "$backup/retired-3PO.app"
mv "$staging" "$installed"

# 6. Verify the installation before any launch.
codesign --verify --deep --strict "$installed" || fail "installed signature is invalid; restore from $backup/previous-3PO.app"
diff -rq "$candidate" "$installed" >/dev/null || fail "installed files differ from the candidate"
python3 scripts/packaging/record-digest.py "$support/Dashboard.store" > "$backup/after-install.json"
cmp -s "$backup/before.json" "$backup/after-install.json" || fail "saved records changed during installation; restore from $backup"
cat > "$backup/installation.json" <<JSON
{"installed": "$installed", "candidate": "$candidate", "configuration": "$kind", "sourceCommit": "$(git rev-parse HEAD)", "recordsUnchangedBeforeLaunch": true, "signatureVerified": true}
JSON
print -- "Installed $kind build of $commit. Backup and verification: $backup"
if (( launch )); then open "$installed"; print -- "Launched. Check that one normal 3PO process is running."; fi
