# Windows workflow registry integration

Base: root84a236d87de8afb1a7a1e60d792e816dac5329ac.
Owner worktree: D:/Worktrees/kelpie/capture-observations-20261104.
Resource grant: MAXIS-NATIVE-MCP-6. Computer Use/browser/app/inference work is excluded.

## Root cause and change

Actual native HTTP -> generic MCP playback returned -32601 before reaching the
registered Windows router. The shared descriptor/schema already existed, but
CreateDefaultMcpTools omitted all four workflow entries. DesktopMcpServer builds
its extension configuration from that registry, so callable routes were absent.

Register play-script, abort-script, get-script-status, and get-script-artifact for
Windows Chromium only. Reuse existing generated NativeExtensionInputSchema and
NativeExtensionMutates metadata through the real registry C API. Status/artifact
are reads; play/abort remain mutations. Existing platform/renderer and native-route
filters, authorization, owner checks, and read-only policy remain authoritative.
No custom input schema or additional Nessie grant is introduced.

The separate metadata-index/:scope draft is preserved in a named Git stash while
this urgent registry fix is checked and committed independently.

## Verification

Fresh Maxis preflight: CPU13%, free physical memory19,169,204KiB.
All task temp/logs: D:/Temp/capture-observations-20261104.
Native outputs: D:/BuildArtifacts/kelpie/capture-observations-20261104/native.

- [x] pnpm.cmd lint; pnpm.cmd build: pass.
- [x] pnpm.cmd -r --workspace-concurrency=1 test --maxWorkers=1 --minWorkers=1:
  pass, shared127 and CLI678; 64 existing CLI skips.
- [x] cmake --build D:/BuildArtifacts/kelpie/capture-observations-20261104/native --config Release --target test_mcp_registry
  test_native_extensions test_browser_gateway --parallel 1.
- [x] ctest --test-dir D:/BuildArtifacts/kelpie/capture-observations-20261104/native -C Release
  -R "test_mcp_registry|test_native_extensions|test_browser_gateway" --output-on-failure:
  pass3/3,2.48s. The first focused test compile omitted the required nullptr names
  argument to Extensions; corrected and rebuilt. Existing NDEBUG/UNDEBUG test-option
  warnings remain. Logs: mcp6-lint.log, mcp6-build.log, mcp6-test.log,
  mcp6-native-build.log and mcp6-native-test.log in the task temp directory.
- [ ] Native owner rebuild/retest of real Windows HTTP -> generic MCP flow.

Focused durable checks:
- test_mcp_registry: exact inventory counts, Windows+Chromium admission and rejection
  on other platforms/engines.
- test_native_extensions: actual C API registry descriptors into BrowserGateway;
  generic extension authorization/dispatch for all four tools; generated schema
  identity, no host-only secret binding fields, read classification/read-only filtering,
  absent-router suppression, unknown owner field and oversized chunk refusal.
- test_browser_gateway: existing strict schema/default, authorization, reference,
  uncertainty, and generic MCP contracts.

Core tests exercise the supported native registry/gateway interface. They do not
establish native application playback/capture acceptance; the Windows owner verifies
that flow after consuming this fix. No application build or browser was launched here.
