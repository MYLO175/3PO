// Read-only end-to-end check of a rendered or installed plugin connection.
import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { Client } from '../../../MCPBridge/node_modules/@modelcontextprotocol/sdk/dist/esm/client/index.js';
import { StdioClientTransport } from '../../../MCPBridge/node_modules/@modelcontextprotocol/sdk/dist/esm/client/stdio.js';

const [host, suppliedRoot] = process.argv.slice(2);
if (!['openai', 'claude'].includes(host) || !suppliedRoot) {
  throw new Error('Usage: node check-connection.mjs openai|claude PLUGIN_ROOT');
}
const root = resolve(suppliedRoot);
const file = host === 'openai' ? 'mcp.json' : '.mcp.json';
const configuration = JSON.parse(await readFile(resolve(root, file), 'utf8')).mcpServers['3po-workspace'];
const expand = value => value.replaceAll('${PLUGIN_ROOT}', root).replaceAll('${CLAUDE_PLUGIN_ROOT}', root);
const transport = new StdioClientTransport({
  command: configuration.command.startsWith('./') ? resolve(root, configuration.command) : expand(configuration.command),
  args: (configuration.args ?? []).map(expand),
  cwd: configuration.cwd ? resolve(root, expand(configuration.cwd)) : root,
  stderr: 'pipe',
});
const client = new Client({ name: '3po-plugin-' + host + '-connection-check', version: '0.1.0' });
const decode = result => {
  if (result.isError) throw new Error('The read-only 3PO tool check failed.');
  return result.structuredContent ?? JSON.parse(result.content.find(item => item.type === 'text').text);
};
try {
  await client.connect(transport);
  const { tools } = await client.listTools();
  const about = decode(await client.callTool({ name: 'about_3po', arguments: {} }));
  const instructions = decode(await client.callTool({ name: 'read_instructions', arguments: { target: 'assistant' } }));
  const reminders = decode(await client.callTool({ name: 'read_reminders', arguments: {} }));
  const projects = decode(await client.callTool({
    name: 'read_life_items',
    arguments: { deleted: false, dueBefore: null, maxMinutes: null, query: '', root: null, unfinished: false },
  }));
  if (about.app !== '3PO' || instructions.target !== 'assistant' || !Array.isArray(reminders.reminders) || !Array.isArray(projects.items)) {
    throw new Error('The 3PO readback did not match the expected contract.');
  }
  process.stdout.write(JSON.stringify({
    host, server: client.getServerVersion(),
    toolCount: tools.length,
    toolNames: tools.map(tool => tool.name).sort(),
    mutationCount: tools.filter(tool => tool.annotations?.readOnlyHint === false).length,
    approvalLocation: about.permissions?.approvalLocation,
    instructionsRead: true, reminderCount: reminders.reminders.length,
    projectRecordCount: projects.items.length, liveWrites: 0, modelRequests: 0,
  }, null, 2) + '\n');
} finally {
  await client.close();
}
