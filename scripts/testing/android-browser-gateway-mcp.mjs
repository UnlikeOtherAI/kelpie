// Standard MCP SDK acceptance. Credentials arrive on stdin and are never printed.
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { pathToFileURL } from 'node:url';

const require = createRequire(new URL('../../packages/cli/package.json', import.meta.url));
const { Client } = await import(pathToFileURL(require.resolve('@modelcontextprotocol/sdk/client/index.js')));
const { StreamableHTTPClientTransport } = await import(pathToFileURL(require.resolve('@modelcontextprotocol/sdk/client/streamableHttp.js')));
let input = '';
for await (const chunk of process.stdin) input += chunk;
const { base, token, tab } = JSON.parse(input);
const client = new Client({ name: 'android-gateway-verification', version: '1.0.0' });
const transport = new StreamableHTTPClientTransport(new URL('/mcp', base), {
  requestInit: { headers: { Authorization: `Bearer ${token}` } },
});
try {
  await client.connect(transport);
  const catalog = await client.listTools();
  assert.deepEqual(catalog.tools.map(tool => tool.name), [
    'kelpie_browser_control', 'kelpie_extensions', 'kelpie_extension_tools', 'kelpie_extension',
  ]);
  const capabilities = await client.callTool({ name: 'kelpie_browser_control', arguments: {
    request: { version: 1, method: 'capabilities' },
  } });
  const decode = result => JSON.parse(result.content.find(item => item.type === 'text').text);
  assert.equal(decode(capabilities).ok, true);
  const refusal = await client.callTool({ name: 'kelpie_browser_control', arguments: {
    request: { version: 1, method: 'tab.click', tabId: tab, params: { ref: 'unobserved' } },
  } });
  assert.equal(decode(refusal).ok, false);
  const image = await client.callTool({ name: 'kelpie_browser_control', arguments: {
    request: { version: 1, method: 'tab.screenshot', tabId: tab },
  } });
  assert.equal(image.content[0].type, 'image');
  console.log('PASS standard MCP SDK initialize/list/call/refusal/image journey');
} finally {
  await client.close();
}
