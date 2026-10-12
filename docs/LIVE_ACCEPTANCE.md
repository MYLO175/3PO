# Installed reliability acceptance

Latest candidate code checkpoint: `a1f4946`, including contextual Feedback and foreground prerequisite recovery. Installed 12 October 2026 at 18:14 London / 17:14 UTC, stable path and bundle identity. Signed executable SHA-256: `d56b9b67ab4052da5e969104964ee66e74059948d396ae24f6e0a3936fd4a45f`; debug library: `74c3482c9c901f729432d7e14a2e5038e8fc840ec8c4894171e225a42166be3e`. Full verified backup: `~/Library/Application Support/3PO Development Backups/20261012-171530-prerequisite-recovery`.

The original reliability candidate `a63b2da` was installed at 10:40 UTC. Its checks and physical sleep/wake observations below remain useful historical evidence, not 72-hour acceptance of the newer installed binary. The latest combined build passes seven relevant source-free suites, AssistantService 140 and app-memory 137/62/11; installation preserved all 64 records and 12 support files. Subsequent operator continuation preserved all 294 prior canonical conversation turns, seven protected records and earlier action receipts. One already-confirmed London visit was created/read back; unsupported iCloud tentative availability required a labelled title/note representation and its failed claim remains. Operator-assisted work is not normal unassisted use or proof of automatic model recovery.

## Already verified

- Full isolated inventory59/59; actual assistant50, learning22, heartbeat124 and persisted budget159 contracts.
- Signed candidate app-memory3/3 (137/137,62/62,11/11), disposable native24/24 with cleanup, configured-model5/5 (61 assertions/nine fictional requests).
- Idle quit and complete private backup of the personal store, images, encrypted WhatsApp files, preferences and previous signed application; all34 records and13 support files matched the original. Backup and two previous bundles are outside Git under `~/Library/Application Support/3PO Development Backups/20261012-113832-reliability`.
- Signature and executable/debug-library readback after installation; normal launch and a second clean quit/relaunch.
- Protected conversation/draft/memory/project/layout/action/creation/queue records and original images pass10/10 preservation checks. Legacy conversation bytes remain unchanged. Calendar returns to today on mount; source-exclusion Sets retain exact membership despite JSON ordering. These two documented normalisations are recorded separately from raw-byte identity. All saved application preferences remain unchanged.
- Native typing (one temporary space, restored exactly), Project navigation, return to Today and normal relaunch retain the original unsent draft and original conversation identities. No message was sent, Review item approved/dismissed or personal native record edited.
- First ordinary scheduled run on this build: 12 October 11:34:05–11:35:21 UTC / 12:34–12:35 London. Context, Email review, Suggestions & drafts and Today's brief all finished Done, with six model requests, two checked Mail accounts, no collection issues and no saved failure. More bounded work remains pending; the account returned to idle without a failure retry. The latest widget record references this exact completed run. Original morning records and notification claims remain unchanged; the original draft count and completed queue states remain. There is no current-day morning record, so the existing widget-only path is correct. Private metadata snapshots `20261012-1132.json` and `20261012-1135.json` preserve the comparison. One successful cycle does not establish sustained operation or physical sleep/wake.
- First physical closed-laptop/full-wake observation: 12 October Clamshell Sleep at 13:21:54 London, followed by dark/maintenance wakes and DarkWake to FullWake at 14:29:29. No saved review or additional heartbeat call claim occurred in that interval. One fresh review began 2.647 seconds after full wake, rather than waiting another hour or replaying missed intervals. It failed during email analysis after one claimed request with a connection-failure message; the earlier brief, morning records, notification claims and completed queues remained. Fresh retry is scheduled for 15:29 London. Private `20261012-135325.json` and `20261012-135325-assessment.json` retain this evidence. Eight preservation/timing comparisons pass; the review itself failed. This observes closed/dark-wake waiting and wake catch-up, not an in-flight sleep interruption or sustained recovery.

The pre-18:14 backup now contains canonical conversation chunks including the human's normal 12 October chat and its original failed Calendar reply. Later authorised operator continuation retained every prior canonical turn and legacy/metadata record while extending only the active chunk/index. This adds real changed-turn/chunk preservation evidence; fictional unknown-field/migration checks remain separate, and several days of normal use are still required.

## Required before full-plan completion

Keep the goal open until at least72 real elapsed hours and at least three distinct local days of normal use have produced evidence for the installed candidate. Several snapshots on one day or a simulated clock do not satisfy this.

On 12 October the user confirmed they will use 3PO casually, including periods when the laptop is closed. Observe that ordinary use; no scripted personal requests or required daily test routine. The latest candidate's elapsed-time threshold is 15 October at 17:14 UTC / 18:14 London at the earliest. Time passing alone does not satisfy the remaining evidence gates.

- Inspect fresh owned heartbeat runs: persistent claims/stages, current brief, independently collected Mail coverage, no same-run retry storm or repeated morning chat/notification delivery.
- Inspect physical sleep/lid/wake evidence and relevant app receipts. The OS power log can prove an actual transition; it cannot alone prove every app inference/write guard. Compare actual request/run times and sleep interruption/catch-up records, using focused checks for the covered cancellation boundaries.
- Observe foreground use and normal source/provider changes. Failed/partial work retains its receipts; pending accounts stay pending rather than becoming empty/completed. Explicitly interrupted foreground queues/native claims must not replay automatically.
- Check sustained memory/review usefulness for missed relevant facts, stale beliefs and repeated acknowledged concerns. Do not label lexical retrieval as semantic recall; paraphrase probes remain0/2 and broader semantic work remains a stated product limitation.
- Recheck preservation after normal authorised conversation saves. New human work is expected to change records; compare identities/history/receipts rather than demanding byte equality against the pre-install backup.

Do not manufacture traffic, change source opt-ins/model/credentials/permissions, send messages, run personal manual inference or force an Apple operation to make the observation pass. Do not prevent sleep to conceal a device guard. Only the integration owner performs live acceptance; workers do not access personal sources.

## Read-only metadata snapshots

`scripts/observe-runtime.py` reads the explicit SQLite store without changing its records, and reads the installed executable/process and filtered OS power events. It writes only timestamps, counts, hashed identities, states and flags to a new private file outside any Git checkout. It exports no source/memory/conversation prose, reasoning, credentials or exact account IDs. Missing/unreadable records and unavailable process/power observation are not proof of an empty or successful state.

Schema 2 adds metadata and canonical record hashes for all saved morning records, the latest widget briefs, hashed notification claims and per-lane learning claim times. Keep original morning identities/hashes stable across later widget updates; new local days may add their own morning record. `morningRecords` retains its earlier post-install-only meaning. These comparisons verify saved delivery claims, not whether macOS displayed a notification.

When a current-day morning anchor exists, compare its exact owner/day/identity with the widget's `morningID`. When it does not exist, an owned completed heartbeat may save `widgetOnly=true` with no morning link. Do not require a fabricated morning anchor or create a morning delivery to satisfy a check.

```sh
python3 scripts/observe-runtime.py \
  --store "$HOME/Library/Application Support/Mission Control/Dashboard.store" \
  --app "$HOME/Applications/3PO.app" \
  --since '2026-10-12T10:40:00+00:00' \
  --output "$HOME/Library/Application Support/3PO Development Backups/20261012-113832-reliability/observations/NEW-TIMESTAMP.json"
```

Use a fresh timestamped filename; the script refuses overwrite or output in a Git checkout. It never launches the app, calls inference/source helpers, changes settings or performs native writes. Snapshot results are observation evidence, not a standalone completion verifier. Review their actual scope and the full seven-stage checklist before marking the goal complete.
