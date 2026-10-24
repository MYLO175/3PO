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
sys.dont_write_bytecode = True
import tempfile
import unittest
import uuid

BRIDGE = Path(__file__).resolve().parents[2] / 'scripts/graphiti/bridge.py'
GROUP = 'a' * 64


def fixture(request):
    text = '\n'.join(x['content'] for x in request['messages'])
    name = request['name']
    if name == 'DurableBackground':
        body = request['messages'][-1]['content']
        return {'excerpts': ['Alice studies at Cambridge.'] if 'Alice studies at Cambridge.' in body else []}
    current_match = re.search(r'<(?:CURRENT MESSAGE|EPISODE)>\s*(.*?)\s*</(?:CURRENT MESSAGE|EPISODE)>', text, re.S)
    current = current_match.group(1) if current_match else text
    person = 'Beatrice' if 'Beatrice' in current else 'Alice'
    place = 'Oxford' if 'Oxford' in current else 'Cambridge'
    fact = f'{person} studies at {place}.' + (' This is the current enrolment.' if 'Current enrolment' in current else '')
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
        self.extractions = []

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
                        self.extractions.append((response['name'], reply['result']))
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

    def test_focused_sync_retains_full_snapshot_and_skips_unrelated_pending(self):
        original = episode(key='existing')
        self.successful('sync', episodes=[original])
        target = episode(person='Beatrice', place='Oxford', key='focus')
        unrelated = episode(key='unrelated')
        unrelated['body'] = 'Source type: memory.\nOriginal evidence DATA; Beatrice appears only in boilerplate.\n' + unrelated['body']
        snapshot = [original, unrelated, target]
        done = self.successful('sync', episodes=snapshot, focus_query='bEaTrIcE', max_new_episodes=6)
        self.assertEqual(done['episode_count'], 2)
        self.assertEqual(done['pending_count'], 1)
        self.assertEqual(done['focus_pending_count'], 0)
        manifest = json.loads(next(Path(self.root).rglob('manifest.json')).read_text())
        self.assertEqual(set(manifest['episodes']), {original['id'], target['id']})
        calls = self.calls
        self.successful('sync', episodes=snapshot, focus_query='no matching record', max_new_episodes=6)
        self.assertEqual(self.calls, calls)
        view = self.successful('browse', allowed_episode_ids=[ep['id'] for ep in snapshot])
        self.assertTrue(any('Alice' in f['text'] for f in view['facts']))
        self.assertTrue(any('Beatrice' in f['text'] for f in view['facts']))
        # Focus never hides withdrawal: reconciliation still checks the entire snapshot.
        reset = self.successful('sync', episodes=[target, unrelated], focus_query='no matching record')
        self.assertEqual(reset['episode_count'], 0)
        self.assertEqual(self.calls, calls)

    def test_durable_policy_filters_and_checkpoints_transient_records(self):
        policy = {'memory_policy': 'durable-background-v2'}
        mixed = episode()
        mixed['body'] += ' Meet the tutor at 14:00 tomorrow. Finish the worksheet tonight.'
        transient = episode(key='appointment')
        transient['body'] = 'Meet the tutor at 14:00 tomorrow.'
        # Legacy generation cannot leak through the changed extraction policy.
        self.successful('sync', episodes=[mixed])
        self.assertEqual(self.call('browse', allowed_episode_ids=[mixed['id']], **policy)['type'], 'error')
        done = self.successful('sync', episodes=[mixed, transient], max_new_episodes=2, **policy)
        self.assertEqual(done['episode_count'], 2)
        calls = self.calls
        graph = self.successful('browse', allowed_episode_ids=[mixed['id'], transient['id']], **policy)
        self.assertTrue(graph['facts'])
        self.assertTrue(all('14:00' not in f['text'] and 'worksheet' not in f['text'] for f in graph['facts']))
        self.successful('sync', episodes=[mixed, transient], **policy)
        self.assertEqual(calls, self.calls, 'Empty background selections must not be retried')
        with __import__('unittest.mock', fromlist=['patch']).patch(__name__ + '.fixture', return_value={'excerpts': ['Invented unsupported claim']}):
            invalid = episode(key='bad-excerpt')
            self.assertEqual(self.call('sync', episodes=[mixed, transient, invalid], **policy)['type'], 'error')
        self.assertEqual(self.successful('status')['episode_count'], 2)

    def test_browse_partial_graph_without_inference(self):
        alice, beatrice = episode(), episode('Beatrice', 'Oxford', 'other')
        self.successful('sync', episodes=[alice, beatrice], max_new_episodes=1)
        calls = self.calls
        graph = self.successful('browse', allowed_episode_ids=[alice['id'], beatrice['id']])
        self.assertEqual(graph['episode_count'], 1)
        self.assertEqual(graph['pending_count'], 1)
        self.assertTrue(graph['facts'])
        nodes = {n['id']: n['name'] for n in graph['nodes']}
        for fact in graph['facts']:
            self.assertIn(fact['source'], nodes)
            self.assertIn(fact['target'], nodes)
            self.assertTrue(fact['episode_ids'])
        self.assertEqual(self.calls, calls, 'Browsing must not request extraction')
        self.assertEqual(self.call('browse', allowed_episode_ids=[])['type'], 'error')
        self.successful('clear')
        self.assertEqual(self.successful('browse', allowed_episode_ids=[])['facts'], [])

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

    def test_temporal_compatibility_keeps_contradictions_and_rejects_drift(self):
        import importlib.util
        from datetime import datetime, timezone
        from graphiti_core.edges import EntityEdge
        from graphiti_core.utils.maintenance import edge_operations as operations
        spec = importlib.util.spec_from_file_location('graphiti_temporal_fixture', BRIDGE)
        bridge = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(bridge)
        original = operations._apply_temporal_invalidation
        def date(month, year=2025):
            return datetime(year, month, 1, tzinfo=timezone.utc)
        def edge(start, end=None):
            return EntityEdge(source_node_uuid=str(uuid.uuid4()), target_node_uuid=str(uuid.uuid4()),
                              name='STUDIES_AT', fact='Fictional enrolment', group_id=GROUP,
                              valid_at=start, invalid_at=end, created_at=datetime.now(timezone.utc))
        try:
            bridge.configure_temporal_resolution()
            old, current = edge(date(1)), edge(date(2), date(1, 2100))
            invalidated = operations._apply_temporal_invalidation(current, [old])
            self.assertIsNone(current.expired_at, 'A future end must not expire the current claim')
            self.assertEqual(invalidated, [old])
            self.assertEqual(old.invalid_at, current.valid_at)
            self.assertIsNotNone(old.expired_at, 'Genuine earlier contradictions still expire')
            superseded = edge(date(1))
            operations._apply_temporal_invalidation(superseded, [edge(date(2))])
            self.assertEqual(superseded.invalid_at, date(2))
            self.assertIsNotNone(superseded.expired_at)
            ended = edge(date(1), date(2))
            operations._apply_temporal_invalidation(ended, [])
            self.assertIsNotNone(ended.expired_at, 'Past end dates remain historical')
            operations._apply_temporal_invalidation = lambda *_: []
            bridge._TEMPORAL_PATCHED = False
            with self.assertRaises(bridge.SafeError):
                bridge.configure_temporal_resolution()
        finally:
            operations._apply_temporal_invalidation = original

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

    def test_expired_matches_do_not_consume_current_result_limit(self):
        # The expired and current claims have the same searchable text; filtering
        # only after top-k can return no current answer despite one being indexed.
        expired = episode(key='ended')
        expired['body'] += ' Ended in February.'
        current = episode(key='current')
        current['body'] += ' Current enrolment.'
        self.successful('sync', episodes=[expired, current], max_new_episodes=2)
        full = self.successful('search', query='Alice studies at Cambridge', limit=30,
                               allowed_episode_ids=[expired['id'], current['id']])
        self.assertTrue(any(current['id'] in x['episode_ids'] for x in full['facts']), (full, self.extractions))
        result = self.successful('search', query='Alice studies at Cambridge', limit=1,
                                 allowed_episode_ids=[expired['id'], current['id']])
        self.assertEqual(len(result['facts']), 1, result)
        self.assertEqual(result['facts'][0]['episode_ids'], [current['id']])

    def test_future_end_remains_current_when_related_fact_exists(self):
        expired = episode(key='ended')
        expired['body'] += ' Ended in February.'
        current = episode(key='future-end')
        current['reference_time'] = '2026-01-02T00:00:00Z'
        current['body'] += ' Ends in 2100. Current enrolment.'
        self.successful('sync', episodes=[expired, current], max_new_episodes=2)
        result = self.successful('search', query='Alice studies at Cambridge', limit=30,
                                 allowed_episode_ids=[expired['id'], current['id']])
        self.assertTrue(any(current['id'] in fact['episode_ids'] for fact in result['facts']),
                        'A future end date must not expire a current relationship during related-edge resolution: ' + repr(result))

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
