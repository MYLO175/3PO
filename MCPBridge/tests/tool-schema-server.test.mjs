import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StdioClientTransport } from '@modelcontextprotocol/sdk/client/stdio.js';

const server = fileURLToPath(new URL('../tool-schema-server.mjs', import.meta.url));
const tools = [
  { name: 'read_calendar', description: 'Read fictional calendar occurrences.', inputSchema: { type: 'object', properties: { start: { type: 'string' } }, required: ['start'], additionalProperties: false } },
  { name: 'prepare_brief', description: 'Return a fictional brief.', inputSchema: { type: 'object', properties: { text: { type: ['string', 'null'] } }, required: ['text'], additionalProperties: false } }
];

async function connect(file) {
  const client = new Client({ name: 'fictional-claude-code', version: '1' });
  await client.connect(new StdioClientTransport({ command: process.execPath, args: [server], env: { PATH: process.env.PATH, THREEPO_TOOL_SCHEMA_FILE: file }, stderr: 'pipe' }));
  return client;
}

test('advertises the round tools and never executes a call', async () => {
  const directory = await mkdtemp(join(tmpdir(), '3po-tool-schema-test-'));
  const file = join(directory, 'tools.json');
  await writeFile(file, JSON.stringify(tools), { mode: 0o600 });
  const client = await connect(file);
  try {
    const listed = await client.listTools();
    assert.deepEqual(listed.tools.map(tool => tool.name), ['read_calendar', 'prepare_brief']);
    assert.deepEqual(listed.tools[0].inputSchema, tools[0].inputSchema);
    const outcome = await Promise.race([
      client.callTool({ name: 'read_calendar', arguments: { start: '2026-10-25' } }).then(() => 'returned', () => 'failed'),
      new Promise(resolve => setTimeout(() => resolve('held'), 400))
    ]);
    assert.equal(outcome, 'held', 'a tool call must never produce a result');
  } finally {
    await client.close();
    await rm(directory, { recursive: true, force: true });
  }
});

test('refuses a shared or invalid schema file', async () => {
  const directory = await mkdtemp(join(tmpdir(), '3po-tool-schema-test-'));
  try {
    const shared = join(directory, 'shared.json');
    await writeFile(shared, JSON.stringify(tools), { mode: 0o644 });
    await assert.rejects(connect(shared));
    const invalid = join(directory, 'invalid.json');
    await writeFile(invalid, JSON.stringify([{ name: 'Bad Name', description: '', inputSchema: { type: 'object' } }]), { mode: 0o600 });
    await assert.rejects(connect(invalid));
    const duplicate = join(directory, 'duplicate.json');
    await writeFile(duplicate, JSON.stringify([tools[0], tools[0]]), { mode: 0o600 });
    await assert.rejects(connect(duplicate));
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});
