import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { mkdtemp, writeFile, chmod, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StdioClientTransport } from '@modelcontextprotocol/sdk/client/stdio.js';

test('real MCP stdio handshake, discovery, calls, errors, and isolated clients', async () => {
  const directory = await mkdtemp(join(tmpdir(), '3po-mcp-test-'));
  const token = 'fictional-test-credential-'.repeat(4);
  const requests = [];
  let activeToken = token;
  const bridge = http.createServer(async (request, response) => {
    assert.equal(request.url, '/bridge');
    assert.equal(request.headers.authorization, `Bearer ${activeToken}`);
    const chunks = [];
    for await (const chunk of request) chunks.push(chunk);
    const value = JSON.parse(Buffer.concat(chunks));
    requests.push(value);
    response.setHeader('content-type', 'application/json');
    if (value.method === 'tools/list') response.end(JSON.stringify({ tools: [{ name: 'read_reminders', inputSchema: { type: 'object', properties: {} } }] }));
    else if (value.name === 'read_reminders') response.end(JSON.stringify({ reminders: [{ id: 'fictional', title: 'Read a paper' }] }));
    else if (value.name === 'change_calendar') response.end(JSON.stringify({ requestID: value.arguments.requestID, status: 'completed', verified: true }));
    else response.end(JSON.stringify({ error: 'Read the exact item first. No change was attempted.' }));
  });
  await new Promise(resolve => bridge.listen(0, '127.0.0.1', resolve));
  const configurationFile = join(directory, 'connection.json');
  const configuration = { url: `http://127.0.0.1:${bridge.address().port}/bridge`, token };
  await writeFile(configurationFile, JSON.stringify(configuration), { mode: 0o600 });
  const clients = [];
  async function connect(name) {
    const client = new Client({ name, version: '1' });
    const transport = new StdioClientTransport({ command: process.execPath, args: [fileURLToPath(new URL('../server.mjs', import.meta.url))], env: { PATH: process.env.PATH, THREEPO_MCP_CONNECTION_FILE: configurationFile }, stderr: 'pipe' });
    await client.connect(transport); clients.push(client); return client;
  }
  try {
    const claude = await connect('fictional-claude');
    assert.equal(claude.getServerVersion().name, '3po');
    assert.match(claude.getInstructions(), /permission HERE/);
    assert.match(claude.getInstructions(), /read-only/);
    assert.equal((await claude.listResources()).resources[0].uri, '3po://guide');
    assert.match((await claude.readResource({ uri: '3po://guide' })).contents[0].text, /tool approval/);
    assert.equal((await claude.listPrompts()).prompts[0].name, '3po-assistant');
    assert.match((await claude.getPrompt({ name: '3po-assistant' })).messages[0].content.text, /about_3po/);
    assert.equal((await claude.listTools()).tools[0].name, 'read_reminders');
    const read = await claude.callTool({ name: 'read_reminders', arguments: {} });
    assert.equal(read.structuredContent.reminders[0].id, 'fictional');
    const requestID = '1f6ae9d2-d530-474c-842f-b66edb4ea4d9';
    const pending = await claude.callTool({ name: 'change_calendar', arguments: { requestID } });
    assert.equal(pending.structuredContent.verified, true);
    assert.equal(pending.structuredContent.status, 'completed');
    assert.equal(requests.at(-1).arguments.requestID, requestID);
    const failure = await claude.callTool({ name: 'read_item_details', arguments: {} });
    assert.equal(failure.isError, true);
    assert.match(failure.content[0].text, /exact item/);
    const chatgpt = await connect('fictional-chatgpt-tunnel');
    await chatgpt.callTool({ name: 'read_reminders', arguments: {} });
    const calls = requests.filter(value => value.method === 'tools/call');
    assert.equal(calls[0].client, 'fictional-claude');
    assert.equal(calls.at(-1).client, 'fictional-chatgpt-tunnel');
    assert.notEqual(calls[0].session, calls.at(-1).session);
    assert.equal(new Set(calls.slice(0, 3).map(value => value.session)).size, 1);
    // A restarted app rotates its credential; the adapter rereads it without
    // ever retrying a submitted request or caching a revoked bearer token.
    activeToken = 'rotated-fictional-test-credential-'.repeat(3);
    await writeFile(configurationFile, JSON.stringify({ ...configuration, token: activeToken }));
    await claude.callTool({ name: 'read_reminders', arguments: {} });
    const before = requests.length;
    await chmod(configurationFile, 0o644);
    assert.equal((await claude.callTool({ name: 'read_reminders', arguments: {} })).isError, true);
    assert.equal(requests.length, before, 'insecure discovery is refused before networking');
    await chmod(configurationFile, 0o600);
    await writeFile(configurationFile, JSON.stringify({ ...configuration, url: 'https://example.com/bridge' }));
    assert.equal((await claude.callTool({ name: 'read_reminders', arguments: {} })).isError, true);
    assert.equal(requests.length, before, 'credentials never go to an external address');
    await rm(configurationFile);
    assert.equal((await claude.callTool({ name: 'change_calendar', arguments: { requestID } })).isError, true);
    assert.equal(requests.length, before, 'disabling the bridge does not replay a change');
  } finally {
    await Promise.all(clients.map(client => client.close()));
    await new Promise(resolve => bridge.close(resolve));
    await rm(directory, { recursive: true, force: true });
  }
});
