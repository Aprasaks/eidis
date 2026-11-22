#!/usr/bin/env node
// Read-only JARVIS Chrome DevTools bridge. Requires user-enabled Chrome Remote
// Debugging and explicit Chrome approval. No credentials, cookies, storage,
// screenshots, page contents, or arbitrary JavaScript are requested.
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StdioClientTransport } from '@modelcontextprotocol/sdk/client/stdio.js';
import { summarizePages } from './policy.mjs';

const root = path.dirname(fileURLToPath(import.meta.url));
const chromeServer = path.join(root, 'node_modules/chrome-devtools-mcp/out/Default/gen/src/bin/chrome-devtools-mcp.js');
const timeout = Number(process.env.JARVIS_CHROME_CHECK_TIMEOUT_MS) || 35000;
function print(result) { process.stdout.write(JSON.stringify(result) + '\n'); }

let client;
let timer;
try {
  const env = {
    HOME: process.env.HOME || '', PATH: process.env.PATH || '/usr/bin:/bin',
    TMPDIR: process.env.TMPDIR || '/tmp', LANG: process.env.LANG || 'en_US.UTF-8',
    CHROME_DEVTOOLS_MCP_NO_USAGE_STATISTICS: '1',
    CHROME_DEVTOOLS_MCP_NO_PERFORMANCE_CRUX: '1',
  };
  const transport = new StdioClientTransport({
    command: process.execPath,
    args: [chromeServer, '--autoConnect', '--no-category-input', '--no-category-network',
      '--no-category-debugging', '--no-category-memory', '--no-category-performance',
      '--no-category-emulation', '--no-file-navigations', '--no-javascript-evaluation',
      '--no-usage-statistics', '--no-performance-crux', '--experimentalStructuredContent'],
    cwd: root, env, stderr: 'ignore',
  });
  client = new Client({ name: 'dechive-jarvis-chrome-readonly', version: '0.1.0' });
  timer = setTimeout(() => {
    print({ connected: false, channels: [], error: 'approval_or_connection_timeout' });
    process.exit(2);
  }, timeout);
  await client.connect(transport);
  const result = await client.callTool({ name: 'list_pages', arguments: {} });
  if (result.isError) throw new Error('list_pages_failed');
  clearTimeout(timer);
  print({ connected: true, channels: summarizePages(result) });
} catch {
  if (timer) clearTimeout(timer);
  print({ connected: false, channels: [], error: 'chrome_remote_debugging_or_permission_needed' });
  process.exitCode = 2;
} finally {
  try { await client?.close(); } catch { /* no secret-containing logs */ }
}
