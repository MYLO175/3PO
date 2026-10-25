import { readFile, stat } from 'node:fs/promises';
import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { CallToolRequestSchema, ListToolsRequestSchema } from '@modelcontextprotocol/sdk/types.js';

// Advertises one inference round's 3PO tool schemas to a headless Claude Code
// run. It never executes anything: 3PO reads the completed tool call from the
// CLI's output, stops the run, and executes the call through its own guarded
// tool session. A call is therefore held open until the CLI exits.
const schemaFile = process.env.THREEPO_TOOL_SCHEMA_FILE;
const toolName = /^[a-z][a-z0-9_]{0,63}$/;

async function definitions() {
  if (!schemaFile) throw new Error('No tool schema file was supplied.');
  const info = await stat(schemaFile);
  if (!info.isFile() || info.size > 2_000_000 || (info.mode & 0o077) !== 0 || info.uid !== process.getuid()) throw new Error('The tool schema file is not private.');
  const tools = JSON.parse(await readFile(schemaFile, 'utf8'));
  if (!Array.isArray(tools) || tools.length > 64) throw new Error('The tool schema file is invalid.');
  const names = new Set();
  for (const tool of tools) {
    if (typeof tool?.name !== 'string' || !toolName.test(tool.name) || names.has(tool.name) || typeof tool.description !== 'string'
        || typeof tool.inputSchema !== 'object' || tool.inputSchema === null || tool.inputSchema.type !== 'object') throw new Error('The tool schema file is invalid.');
    names.add(tool.name);
  }
  return tools.map(({ name, description, inputSchema }) => ({ name, description, inputSchema }));
}

const tools = await definitions().catch(error => {
  process.stderr.write(`${error.message}\n`);
  process.exit(1);
});
const server = new Server({ name: 'pa', version: '1.0.0' }, { capabilities: { tools: {} } });
server.setRequestHandler(ListToolsRequestSchema, async () => ({ tools }));
server.setRequestHandler(CallToolRequestSchema, () => new Promise(() => {}));
try {
  await server.connect(new StdioServerTransport());
} catch {
  process.stderr.write('The 3PO tool schema server could not start.\n');
  process.exitCode = 1;
}
