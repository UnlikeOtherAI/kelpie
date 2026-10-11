// Called only after the explicit shared package build. Output belongs to the native build directory.
import { mkdir, writeFile } from 'node:fs/promises';
import { dirname } from 'node:path';
import { z } from '../../packages/shared/node_modules/zod/index.js';
import { BrowserControlRequestSchema, browserControlInputSchema, BROWSER_CONTROL_METHODS, browserControlMutates } from '../../packages/shared/dist/browser-control/protocol.js';
import { BROWSER_CONTROL_DESCRIPTION, BROWSER_CONTROL_DOCUMENTATION } from '../../packages/shared/dist/browser-control/proxy.js';
import { collectBrowserSnapshot } from '../../packages/shared/dist/browser-control/snapshot.js';
import { rememberNativeSnapshot, resolveNativeReference, actOnNativeReference } from '../../packages/shared/dist/browser-control/native-reference.js';
const output = process.argv[2];
if (!output) throw new Error('Expected generated header path');
const inputs = [
  {version:1,method:"tabs.list"},
  {version:1,method:"page.scroll",tabId:"a",params:{deltaY:5}},
  {version:1,method:"tab.type",tabId:"a",params:{ref:"e1",text:"😀".repeat(100)}},
  {version:1,method:"tab.goto",params:{url:"x".repeat(8193)}},
  {version:1,method:"tab.snapshot",params:{maxElements:1001}},
  {version:1,method:"tab.snapshot",params:{maxChars:255}},
  {version:2,method:"tabs.list"},
  {version:1,method:"tabs.list",extra:"SECRET"},
  JSON.parse('{"version":1,"method":"tabs.list","__proto__":{}}'),
  {version:1,method:"tab.goto",params:{url:"ok",unknown:1}},
  {version:1,method:"locator.click",params:{locator:[{kind:"nth",index:1.5}]}},
  {version:1,method:"locator.click",params:{locator:[{kind:"role",role:"button",name:{source:"Save",flags:"i"}}]}},
];
const cases = inputs.map(input => { const result = BrowserControlRequestSchema.safeParse(input); return {input,accepted:result.success,...(result.success ? {output:result.data} : {})}; });
const assets = {
  cases: JSON.stringify(cases),
  request_schema: JSON.stringify(z.toJSONSchema(BrowserControlRequestSchema, { reused: 'ref' })),
  input_schema: JSON.stringify(browserControlInputSchema({ compact: true })),
  methods: JSON.stringify(BROWSER_CONTROL_METHODS),
  mutations: JSON.stringify(BROWSER_CONTROL_METHODS.filter(browserControlMutates)),
  description: BROWSER_CONTROL_DESCRIPTION, documentation: BROWSER_CONTROL_DOCUMENTATION,
  reader: collectBrowserSnapshot.toString(), remember: rememberNativeSnapshot.toString(), resolve: resolveNativeReference.toString(), action: actOnNativeReference.toString(),
};
await mkdir(dirname(output), { recursive: true });
await writeFile(output, '#pragma once\nnamespace kelpie::browser_assets {\n' + Object.entries(assets).map(([name, value]) => `inline constexpr char ${name}[] = R"KELPIE(${value})KELPIE";\n`).join('') + '}\n');
