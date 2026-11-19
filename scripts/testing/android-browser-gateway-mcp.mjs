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
  const extension = async (name, args) => {
    const result = decode(await client.callTool({ name: 'kelpie_extension', arguments: {
      name, arguments: { tabId: tab, ...args },
    } }));
    assert.equal(result.ok, true, JSON.stringify(result));
    return result.value;
  };
  await extension('kelpie_evaluate', { expression: `document.body.insertAdjacentHTML('afterbegin',
    '<div data-selector-fixture><button id="2:entry">Decoy selector action</button><button id="2:entry">Exact selector action</button></div>');
    const selectorFixture = document.querySelector('[data-selector-fixture]');
    selectorFixture.onclick = event => selectorFixture.dataset.clicked = event.target.textContent; true` });
  const found = await extension('kelpie_find_element', { text: 'Exact selector action', role: 'button' });
  assert.equal(found.found, true);
  await extension('kelpie_click', { selector: found.element.selector });
  assert.equal((await extension('kelpie_evaluate', {
    expression: "document.querySelector('[data-selector-fixture]').dataset.clicked",
  })).result, 'Exact selector action');
  await extension('kelpie_evaluate', { expression: "document.querySelector('[data-selector-fixture]').remove(); true" });
  console.log('PASS Android semantic find and selector click activate the intended duplicate-ID button');
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
