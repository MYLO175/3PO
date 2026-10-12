# Installed reliability acceptance

Candidate code checkpoint: `a63b2da`. Installed 12 October 2026 at approximately 11:40 London / 10:40 UTC, stable path and bundle identity. Signed executable SHA-256: `1a8e101673c4c6f3730edc1c433f4c9ae56b3f35f883305cfb83291d64f7e169`; debug library: `ba820ac350c70e0465eeb4f44da247e3e521cb195e4d114951dc72948fc6f453`.

## Already verified

- Full isolated inventory59/59; actual assistant50, learning22, heartbeat124 and persisted budget159 contracts.
- Signed candidate app-memory3/3 (137/137,62/62,11/11), disposable native24/24 with cleanup, configured-model5/5 (61 assertions/nine fictional requests).
- Idle quit and complete private backup of the personal store, images, encrypted WhatsApp files, preferences and previous signed application; all34 records and13 support files matched the original. Backup and two previous bundles are outside Git under `~/Library/Application Support/3PO Development Backups/20261012-113832-reliability`.
- Signature and executable/debug-library readback after installation; normal launch and a second clean quit/relaunch.
- Protected conversation/draft/memory/project/layout/action/creation/queue records and original images pass10/10 preservation checks. Legacy conversation bytes remain unchanged. Calendar returns to today on mount; source-exclusion Sets retain exact membership despite JSON ordering. These two documented normalisations are recorded separately from raw-byte identity. All saved application preferences remain unchanged.
- Native typing (one temporary space, restored exactly), Project navigation, return to Today and normal relaunch retain the original unsent draft and original conversation identities. No message was sent, Review item approved/dismissed or personal native record edited.
- First ordinary scheduled run on this build: 12 October 11:34:05–11:35:21 UTC / 12:34–12:35 London. Context, Email review, Suggestions & drafts and Today's brief all finished Done, with six model requests, two checked Mail accounts, no collection issues and no saved failure. More bounded work remains pending; the account returned to idle without a failure retry. The latest widget record references this exact completed run. Original morning records and notification claims remain unchanged; the original draft count and completed queue states remain. There is no current-day morning record, so the existing widget-only path is correct. Private metadata snapshots `20261012-1132.json` and `20261012-1135.json` preserve the comparison. One successful cycle does not establish sustained operation or physical sleep/wake.

The personal legacy conversation has not yet needed a changed-turn save, so these installed checks prove reading/preservation, not a completed personal chunk migration. Fictional migration, changed-chunk, unknown-field and reopen tests remain the migration evidence until normal authorised use exercises a save.

## Required before full-plan completion

Keep the goal open until at least72 real elapsed hours and at least three distinct local days of normal use have produced evidence for the installed candidate. Several snapshots on one day or a simulated clock do not satisfy this.

On 12 October the user confirmed they will use 3PO casually, including periods when the laptop is closed. Observe that ordinary use; no scripted personal requests or required daily test routine. The elapsed-time threshold is 15 October at 10:40 UTC / 11:40 London at the earliest. Time passing alone does not satisfy the remaining evidence gates.

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
