#!/bin/zsh
# Source-free by default. --list explains the separate integration-only tiers.
set -euo pipefail
cd "$(dirname "$0")/.."
exec python3 - "$@" <<'PY'
import argparse
from datetime import datetime, timezone
import json
import os
import signal
from pathlib import Path
import subprocess
import sys
import tempfile
import time

repository = Path.cwd()
manifest_path = repository / 'scripts/check-suites.json'
manifest = json.loads(manifest_path.read_text())
parser = argparse.ArgumentParser(description='Run 3PO fictional regression checks in an isolated artifact directory.')
parser.add_argument('--tier', default='source-free', choices=list(manifest['tiers']))
parser.add_argument('--suite', action='append', default=[], help='Run only a named suite; repeat for several suites.')
parser.add_argument('--list', action='store_true', help='List suites and their effects without running or creating artifacts.')
parser.add_argument('--timeout', type=float, default=300, help='Maximum seconds per suite; default 300.')
parser.add_argument('--root', help='Parent artifact folder; defaults to MISSIONCONTROL_TEST_ROOT or /private/tmp.')
args = parser.parse_args()
if args.timeout <= 0:
    parser.error('--timeout must be positive')
all_suites = manifest['suites']
if len({suite['id'] for suite in all_suites}) != len(all_suites):
    parser.error('suite manifest has duplicate IDs')
if args.suite:
    wanted = set(args.suite)
    suites = [suite for suite in all_suites if suite['id'] in wanted]
    missing = wanted - {suite['id'] for suite in suites}
    if missing:
        parser.error('unknown suite(s): ' + ', '.join(sorted(missing)))
    wrong_tier = [suite['id'] for suite in suites if suite['tier'] != args.tier]
    if wrong_tier:
        parser.error('suite(s) outside selected tier: ' + ', '.join(wrong_tier))
else:
    suites = [suite for suite in all_suites if suite['tier'] == args.tier]
if args.list:
    tier = manifest['tiers'][args.tier]
    print(args.tier + ': ' + tier['description'])
    for suite in suites:
        command = suite.get('script') or '<signed DEBUG candidate> ' + ' '.join(suite.get('arguments', []))
        print(suite['id'] + ': ' + command + ' [' + ', '.join(suite['effects']) + ']')
    sys.exit(0)
if not manifest['tiers'][args.tier]['automatic']:
    print(args.tier + ' is an integration-owner acceptance tier. Use --list to inspect its fixture modes; this runner does not launch an app or perform native/model work.', file=sys.stderr)
    sys.exit(2)

# Newly added component scripts must be deliberately audited and listed, never silently omitted.
known_scripts = {suite['script'] for suite in all_suites if 'script' in suite}
component_scripts = {'scripts/' + path.name for path in (repository / 'scripts').glob('test*.sh') if path.name != 'test-env.sh'}
unlisted = component_scripts - known_scripts
missing_scripts = known_scripts - component_scripts
if unlisted or missing_scripts:
    parser.error('manifest/script inventory mismatch; unlisted=' + ','.join(sorted(unlisted)) + '; missing=' + ','.join(sorted(missing_scripts)))

parent = Path(args.root or os.environ.get('MISSIONCONTROL_TEST_ROOT', '/private/tmp')).expanduser()
parent.mkdir(parents=True, exist_ok=True)
root = Path(tempfile.mkdtemp(prefix='missioncontrol-check-', dir=parent)).resolve()
(root / 'logs').mkdir()
(root / 'suites').mkdir()
(root / 'modules').mkdir()
(root / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')

def git_output(arguments):
    return subprocess.check_output(['git', *arguments], cwd=repository, text=True).strip()

def now():
    return datetime.now(timezone.utc).isoformat()

report = {'schemaVersion': 1, 'tier': args.tier, 'repository': str(repository),
          'commit': git_output(['rev-parse', 'HEAD']), 'dirty': bool(git_output(['status', '--porcelain'])),
          'startedAt': now(), 'root': str(root), 'suites': [], 'completed': False,
          'counts': {'passed': 0, 'failed': 0, 'interrupted': 0, 'notRun': len(suites)}}

def save_report():
    # Persist progress after each suite; a terminated run remains resumable evidence.
    temporary = root / 'results.json.tmp'
    temporary.write_text(json.dumps(report, indent=2, sort_keys=True) + '\n')
    temporary.replace(root / 'results.json')

save_report()
print('Artifacts: ' + str(root), flush=True)
interrupted = False
for suite in suites:
    log = root / 'logs' / (suite['id'] + '.log')
    suite_root = root / 'suites' / suite['id']
    suite_root.mkdir()
    environment = os.environ.copy()
    environment['MISSIONCONTROL_TEST_ROOT'] = str(suite_root)
    environment['MISSIONCONTROL_TEST_MODULE_CACHE'] = str(root / 'modules')
    environment['DEVELOPER_DIR'] = '/Applications/Xcode.app/Contents/Developer'
    start = time.monotonic()
    entry = {'id': suite['id'], 'command': [suite['script']], 'startedAt': now(), 'log': str(log), 'artifacts': str(suite_root)}
    report['suites'].append(entry)
    report['counts']['notRun'] -= 1
    save_report()
    try:
        with log.open('w') as stream:
            process = subprocess.Popen([str(repository / suite['script'])], cwd=repository, env=environment,
                                       stdout=stream, stderr=subprocess.STDOUT, start_new_session=True)
            entry['processID'] = process.pid
            save_report()
            try:
                code = process.wait(timeout=args.timeout)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait()
                code = 124
                entry['reason'] = 'suite timeout'
            except KeyboardInterrupt:
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait()
                raise
        entry['exitCode'] = code
        entry['status'] = 'passed' if code == 0 else 'failed'
    except KeyboardInterrupt:
        entry['exitCode'] = 130
        entry['status'] = 'interrupted'
        interrupted = True
    except OSError as error:
        entry['exitCode'] = 127
        entry['status'] = 'failed'
        entry['error'] = str(error)
        log.write_text(str(error) + '\n')
    entry['seconds'] = round(time.monotonic() - start, 3)
    entry['finishedAt'] = now()
    report['counts'][entry['status']] += 1
    save_report()
    print(entry['status'].upper() + ' ' + suite['id'] + ' (' + str(entry['seconds']) + 's)' +
          ('' if entry['status'] == 'passed' else ' — ' + str(log)), flush=True)
    if interrupted:
        break
report['completed'] = not interrupted
report['finishedAt'] = now()
save_report()
counts = report['counts']
print(str(counts['passed']) + ' passed; ' + str(counts['failed']) + ' failed; ' + str(counts['interrupted']) + ' interrupted; ' + str(counts['notRun']) + ' not run.', flush=True)
print('Report: ' + str(root / 'results.json'), flush=True)
sys.exit(130 if interrupted else 1 if counts['failed'] else 0)
PY
