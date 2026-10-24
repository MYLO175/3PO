#!/usr/bin/env python3
"""Actual Graphiti/FalkorDB/ONNX integration; extraction responses are scripted fixtures."""
import json
import os
from pathlib import Path
import re
import subprocess
import signal
import time
import sys
import tempfile
import unittest
import uuid

BRIDGE = Path(__file__).resolve().parents[2] / 'scripts/graphiti/bridge.py'
GROUP = 'a' * 64


def fixture(request):
    text = '\n'.join(x['content'] for x in request['messages'])
    name = request['name']
    current_match = re.search(r'<(?:CURRENT MESSAGE|EPISODE)>\s*(.*?)\s*</(?:CURRENT MESSAGE|EPISODE)>', text, re.S)
    current = current_match.group(1) if current_match else text
    person = 'Beatrice' if 'Beatrice' in current else 'Alice'
    place = 'Oxford' if 'Oxford' in current else 'Cambridge'
    fact = f'{person} studies at {place}.'
    entities = [{'name': person, 'entity_type_id': 0}, {'name': place, 'entity_type_id': 0}]
    edge = {'source_entity_name': person, 'target_entity_name': place,
            'relation_type': 'STUDIES_AT', 'fact': fact, 'valid_at': '2026-01-01T00:00:00Z',
            'invalid_at': ('2100-01-01T00:00:00Z' if 'Ends in 2100' in current else
                           '2026-02-01T00:00:00Z' if 'Ended in February' in current else None)}
    if name == 'ExtractedEntities':
        return {'extracted_entities': entities}
    if name == 'CombinedExtraction':
        return {'extracted_entities': entities, 'edges': [edge]}
    if name == 'ExtractedEdges':
        return {'edges': [edge]}
    if name == 'NodeResolutions':
        return {'entity_resolutions': []}
    if name == 'EdgeDuplicate':
        return {'duplicate_facts': [], 'contradicted_facts': []}
    if name == 'EntitySummary':
        return {'summary': fact}
    if name == 'SummarizedEntities':
        return {'summaries': []}
    if name == 'BatchEdgeTimestamps':
        return {'timestamps': [{'valid_at': '2026-01-01T00:00:00Z', 'invalid_at': None}]}
    raise AssertionError('Unexpected fixture schema: ' + name)


def episode(person='Alice', place='Cambridge', key='person', revision='1'):
    return {'id': str(uuid.uuid5(uuid.NAMESPACE_URL, key + ':' + revision)), 'reference_key': key,
            'revision': revision, 'name': 'Fictional university memory',
            'body': f'{person} studies at {place}.', 'reference_time': '2026-01-01T00:00:00Z'}


class EngineTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='3po-graphiti-engine-', dir='/private/tmp')
        self.root = self.temporary.name + '/db'
        self.calls = 0

    def tearDown(self):
        self.temporary.cleanup()

    def call(self, operation, fail=False, **kwargs):
        request = {'protocol': 1, 'operation': operation, 'database_path': self.root, 'group_id': GROUP, **kwargs}
        process = subprocess.Popen([sys.executable, str(BRIDGE)], stdin=subprocess.PIPE,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        process.stdin.write(json.dumps(request) + '\n')
        process.stdin.flush()
        try:
            for line in process.stdout:
                response = json.loads(line)
                if response['type'] == 'llm_request':
                    self.calls += 1
                    if fail:
                        reply = {'type': 'llm_response', 'id': response['id'], 'error': 'Fictional failure'}
                    else:
                        reply = {'type': 'llm_response', 'id': response['id'], 'result': fixture(response)}
                    process.stdin.write(json.dumps(reply) + '\n')
                    process.stdin.flush()
                else:
                    process.wait(timeout=20)
                    stderr = process.stderr.read()
                    self.assertEqual(process.returncode, 0, stderr)
                    self.assertEqual(stderr, '', 'Private helper must not emit dependency logs')
                    return response
            self.fail('Helper ended without result: ' + process.stderr.read())
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
            process.stdin.close()
            process.stdout.close()
            process.stderr.close()

    def successful(self, operation, **kwargs):
        response = self.call(operation, **kwargs)
        self.assertEqual(response['type'], 'result', response)
        return response['result']

    def test_engine_lifecycle(self):
        alice, beatrice = episode(), episode('Beatrice', 'Oxford', 'other')
        first = self.successful('sync', episodes=[alice, beatrice], max_new_episodes=1)
        self.assertEqual(first['episode_count'], 1)
        self.assertEqual(first['pending_count'], 1)
        self.assertEqual(self.successful('status')['pending_count'], 1)
        self.assertGreater(self.calls, 0)
        second = self.successful('sync', episodes=[alice, beatrice])
        self.assertEqual(second['episode_count'], 2)
        calls = self.calls
        unchanged = self.successful('sync', episodes=[alice, beatrice])
        self.assertEqual(unchanged['generation'], second['generation'])
        self.assertEqual(calls, self.calls)
        found = self.successful('search', query='Where does Alice study?', allowed_episode_ids=[alice['id'], beatrice['id']])
        self.assertTrue(any('Alice' in x['text'] for x in found['facts']), found)
        self.assertTrue(all(x['episode_ids'] for x in found['facts']))
        self.assertEqual(calls, self.calls, 'Search must use real local embeddings, with no LLM call')
        withdrawn = self.call('search', query='Alice', allowed_episode_ids=[alice['id']])
        self.assertEqual(withdrawn['type'], 'error')
        revised = episode(place='Oxford', revision='2')
        self.assertEqual(self.call('search', query='Alice', allowed_episode_ids=[revised['id']])['type'], 'error')
        rebuilt = self.successful('sync', episodes=[revised])
        self.assertEqual(rebuilt['episode_count'], 1)
        found = self.successful('search', query='Where does Alice study?', allowed_episode_ids=[revised['id']])
        self.assertTrue(any('Oxford' in x['text'] for x in found['facts']), found)
        self.assertFalse(any('Cambridge' in x['text'] or 'Beatrice' in x['text'] for x in found['facts']), found)
        isolated = self.successful('search', group_id='b' * 64, query='Alice', allowed_episode_ids=[revised['id']])
        self.assertEqual(isolated['facts'], [])
        cleared = self.successful('clear')
        self.assertEqual(cleared['episode_count'], 0)
        self.assertEqual(self.successful('search', query='Alice', allowed_episode_ids=[])['facts'], [])

    def test_failed_revision_fails_closed_without_retry(self):
        original, changed = episode(), episode(place='Oxford', revision='2')
        self.successful('sync', episodes=[original])
        before = self.calls
        failed = self.call('sync', episodes=[changed], fail=True)
        self.assertEqual(failed['type'], 'error')
        self.assertEqual(self.calls - before, 1)
        self.assertEqual(self.successful('status')['episode_count'], 0)
        self.assertEqual(self.successful('search', query='Alice', allowed_episode_ids=[changed['id']])['facts'], [])
        self.assertEqual(self.successful('sync', episodes=[changed])['episode_count'], 1)

    def test_temporal_end_dates(self):
        future = episode()
        future['body'] += ' Ends in 2100.'
        past = episode('Beatrice', 'Oxford', 'past')
        past['body'] += ' Ended in February.'
        self.successful('sync', episodes=[future, past], max_new_episodes=2)
        found = self.successful('search', query='University studies',
                                allowed_episode_ids=[future['id'], past['id']])
        self.assertTrue(any('Alice' in x['text'] for x in found['facts']), found)
        self.assertFalse(any('Beatrice' in x['text'] for x in found['facts']), found)
        self.assertTrue(any(x['invalid_at'].startswith('2100') for x in found['facts']))

    def test_successful_checkpoint_survives_next_episode_failure(self):
        episodes = [episode(), episode('Beatrice', 'Oxford', 'other')]
        initial = self.successful('sync', episodes=episodes)
        self.assertEqual(initial['episode_count'], 1)
        before = self.calls
        self.assertEqual(self.call('sync', episodes=episodes, fail=True)['type'], 'error')
        self.assertEqual(self.calls - before, 1)
        retained = self.successful('status')
        self.assertEqual(retained['indexed_episode_ids'], initial['indexed_episode_ids'])
        self.assertEqual(retained['generation'], initial['generation'])
        self.assertEqual(self.successful('sync', episodes=episodes)['episode_count'], 2)

    def test_cancellation_and_hard_kill_stop_owned_server(self):
        import psutil
        for termination in (signal.SIGTERM, signal.SIGKILL):
            request = {'protocol': 1, 'operation': 'sync', 'database_path': self.root,
                       'group_id': GROUP, 'episodes': [episode()]}
            process = subprocess.Popen([sys.executable, str(BRIDGE)], stdin=subprocess.PIPE,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            process.stdin.write(json.dumps(request) + '\n')
            process.stdin.flush()
            first = json.loads(process.stdout.readline())
            self.assertEqual(first['type'], 'llm_request', first)
            settings = next(Path(self.root).rglob('*.settings'))
            server_pid = int(Path(json.loads(settings.read_text())['pidfile']).read_text())
            self.assertTrue(psutil.pid_exists(server_pid))
            busy = self.call('status')
            self.assertEqual(busy['type'], 'error')
            process.send_signal(termination)
            process.wait(timeout=8)
            deadline = time.monotonic() + 6
            while psutil.pid_exists(server_pid) and time.monotonic() < deadline:
                time.sleep(0.05)
            self.assertFalse(psutil.pid_exists(server_pid), 'Owned database daemon leaked')
            process.stdin.close()
            process.stdout.close()
            process.stderr.close()
            self.assertEqual(self.successful('status')['episode_count'], 0)
            self.successful('clear')

    def test_protocol_validation(self):
        self.assertEqual(self.call('search', query='Alice')['type'], 'error')
        self.assertEqual(self.call('sync', episodes=[episode(), episode()])['type'], 'error')
        self.assertEqual(self.call('sync', episodes=[], max_new_episodes=9)['type'], 'error')


if __name__ == '__main__':
    unittest.main(verbosity=2)
