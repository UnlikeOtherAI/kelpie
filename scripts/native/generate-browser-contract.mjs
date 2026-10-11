// Called only after the explicit shared package build. Output belongs to the native build directory.
import { mkdir, writeFile } from 'node:fs/promises';
import { dirname } from 'node:path';
import { z } from '../../packages/shared/node_modules/zod/index.js';
import { BrowserControlRequestSchema, browserControlInputSchema, BROWSER_CONTROL_METHODS, browserControlMutates } from '../../packages/shared/dist/browser-control/protocol.js';
import { BROWSER_CONTROL_DESCRIPTION, BROWSER_CONTROL_DOCUMENTATION } from '../../packages/shared/dist/browser-control/proxy.js';
import { collectBrowserSnapshot } from '../../packages/shared/dist/browser-control/snapshot.js';
import { rememberNativeSnapshot, resolveNativeReference, actOnNativeReference } from '../../packages/shared/dist/browser-control/native-reference.js';
import { sharedBrowserTools } from '../../packages/shared/dist/extension-tools.js';
import { sharedAiLoadTool, sharedAiAskTool, sharedAiEndpointTools } from '../../packages/shared/dist/extension-ai-tools.js';
const extensionTools = [...sharedBrowserTools, sharedAiLoadTool, sharedAiAskTool, ...sharedAiEndpointTools];
const endpointOf = tool => tool.method.startsWith('ai-') ? tool.method : tool.name.slice(7).replaceAll('_', '-');
const extensionSchemas = Object.fromEntries(extensionTools.map(tool => {
  const { device, ...fields } = tool.schema;
  // Native requests own routing; device selection is only a CLI argument. Preserve
  // the same fields forwarded by bodyFromArgs, including screenshot resolution defaults.
  const shape = { timeout: z.number().int().min(1).max(30000).optional(), windowId: z.string().optional(), generation: z.number().int().nonnegative().optional(), ...fields };
  if (tool.name === 'kelpie_screenshot' || tool.name === 'kelpie_screenshot_annotated') shape.resolution = shape.resolution.default('viewport');
  if (tool.method === 'ai-endpoint-save') {
    delete shape.apiKeyEnv; // A CLI-host environment variable cannot be resolved on a device.
  }
  if (tool.method === 'ai-load') shape.contextSize = z.number().int().min(256).max(8192).optional();
  if (tool.method === 'ai-infer') shape.messages = z.array(z.record(z.string(), z.unknown())).optional();
  const schema = z.toJSONSchema(z.strictObject(shape), { unrepresentable: 'any' });
  return [endpointOf(tool), schema];
}));
// Fail the native build if an authoritative schema requires validation we do not implement.
const supported = new Set(['$schema', '$defs', '$ref', 'type', 'properties', 'required', 'additionalProperties',
  'description', 'enum', 'const', 'anyOf', 'oneOf', 'minimum', 'maximum', 'exclusiveMinimum', 'exclusiveMaximum',
  'minLength', 'maxLength', 'pattern', 'propertyNames', 'items', 'minItems', 'maxItems', 'default']);
function auditSchema(schema) {
  if (typeof schema === 'boolean') return;
  for (const [key, value] of Object.entries(schema)) {
    if (!supported.has(key)) throw new Error(`Unsupported native schema keyword: ${key}`);
    if (key === 'properties' || key === '$defs') Object.values(value).forEach(auditSchema);
    else if (key === 'anyOf' || key === 'oneOf') value.forEach(auditSchema);
    else if (['items', 'additionalProperties', 'propertyNames'].includes(key)) auditSchema(value);
  }
}
Object.values(extensionSchemas).forEach(auditSchema);
const sample = schema => {
  if (schema.const !== undefined) return schema.const;
  if (schema.enum) return schema.enum[0];
  if (schema.anyOf) return sample(schema.anyOf[0]);
  if (schema.type === 'object') return Object.fromEntries((schema.required ?? []).map(key => [key, sample(schema.properties[key])]));
  if (schema.type === 'array') return [];
  if (schema.type === 'number' || schema.type === 'integer') return schema.minimum ?? 1;
  if (schema.type === 'boolean') return true;
  if (schema.type === 'null') return null;
  return 'sample1';
};
const extensionCases = extensionTools.map(tool => {
  const schema = extensionSchemas[endpointOf(tool)];
  const body = tool.bodyFromArgs({device:'fixture', ...sample(schema)});
  return {endpoint:endpointOf(tool), body};
});
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
  extension_schemas: JSON.stringify(extensionSchemas),
  extension_cases: JSON.stringify(extensionCases),
  request_schema: JSON.stringify(z.toJSONSchema(BrowserControlRequestSchema, { reused: 'ref' })),
  input_schema: JSON.stringify(browserControlInputSchema({ compact: true })),
  methods: JSON.stringify(BROWSER_CONTROL_METHODS),
  mutations: JSON.stringify(BROWSER_CONTROL_METHODS.filter(browserControlMutates)),
  description: BROWSER_CONTROL_DESCRIPTION, documentation: BROWSER_CONTROL_DOCUMENTATION,
  reader: collectBrowserSnapshot.toString(), remember: rememberNativeSnapshot.toString(), resolve: resolveNativeReference.toString(), action: actOnNativeReference.toString(),
};
await mkdir(dirname(output), { recursive: true });
// MSVC limits individual and concatenated string literals. UTF-8 byte arrays
// also preserve arbitrary quotes/raw-string delimiters in authoritative assets.
const array = (name, value) => {
  const bytes = [...Buffer.from(value, 'utf8'), 0];
  const rows = [];
  for (let offset = 0; offset < bytes.length; offset += 32) {
    rows.push(bytes.slice(offset, offset + 32).map(byte => byte < 128 ? String(byte) : `static_cast<char>(${byte})`).join(','));
  }
  return `inline constexpr char ${name}[] = {\n${rows.join(',\n')}\n};\n`;
};
await writeFile(output, '#pragma once\nnamespace kelpie::browser_assets {\n' + Object.entries(assets).map(([name, value]) => array(name, value)).join('') + '}\n');
