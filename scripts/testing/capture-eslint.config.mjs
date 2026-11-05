const globals = Object.fromEntries([
  "AbortController", "AbortSignal", "Buffer", "DOMException", "URL",
  "URLSearchParams", "TextDecoder", "TextEncoder", "clearInterval",
  "clearTimeout", "console", "fetch", "performance", "process",
  "queueMicrotask", "setInterval", "setTimeout", "structuredClone",
  "document", "window", "location", "history", "navigator", "sessionStorage", "frameElement", "Element",
  "HTMLElement", "HTMLInputElement", "HTMLTextAreaElement", "HTMLSelectElement",
  "HTMLButtonElement", "HTMLAnchorElement", "Node", "NodeFilter", "Event",
  "MouseEvent", "PointerEvent", "InputEvent", "KeyboardEvent", "getComputedStyle",
  "innerWidth", "innerHeight", "devicePixelRatio", "scrollX", "scrollY",
  "visualViewport", "requestAnimationFrame", "cancelAnimationFrame",
].map((name) => [name, "readonly"]));

export default [{
  files: [
    "tests/capture/*.mjs",
    "tests/linux/{run-native-capture-acceptance,adversary-diagnostics,artifact-protocol-acceptance,finalize-fault,native-lifecycle,native-sandbox,preinput-replacement,verify-native-replay,run-g08,run-gif-pointer-model,verify-g08-backing,gif-runtime-evidence}.mjs",
    "tests/macos/runtime-*.mjs",
    "tests/windows/lib/*.mjs",
    "tests/windows/{run-*,capture-*,g08-*,wgc-*,viewport-diagnostic-*,native-window-*,combine-g08-native-timeline,probe-script-fixture,safe-cli-failure}.mjs",
  ],
  languageOptions: { ecmaVersion: "latest", sourceType: "module", globals },
  rules: { "no-undef": "error" },
}];
