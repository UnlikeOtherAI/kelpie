# Trusted native workflow runtime profiles

Source checkpoint: unit/runtime verification pending. Root authorized a local
Minis-only bounded test mirror because Maxis remains overloaded. This checkpoint
does not claim successful tests or new shipping runtime acceptance.

The four existing generated-schema workflow descriptors now cover compiled
macOS WebKit/Chromium bindings, always windowed/UI-required/non-headless, and
Linux Chromium windowed versus offscreen profiles. Linux windowed requires UI;
only the supported offscreen machine path has requires_ui:false,
allowed_headless:true. iOS/Android profiles and existing Windows metadata remain
unchanged. No rich schema or public workflow operation is duplicated.

ToolRuntimeProfile.runtime_mode defaults to windowed. Shared
AvailabilityForPlatform/SupportsRuntime and McpRegistry projection methods accept
a trusted mode argument, preserving existing windowed defaults and C APIs.
Unknown modes yield no catalogue/capability support. DesktopApp rejects an
unknown mode before engine initialization. C++ DesktopApp::Config.runtime_mode
propagates to DesktopMcpServer::Config.runtime_mode; neither is accepted from
HTTP/MCP request bodies. Forged status arguments remain strict schema errors.

The Linux owner consumes only native launch parsing:
runtime.runtime_mode = headless ? "offscreen" : "windowed", including outbound
MCP job config. The default/legacy C API is a windowed catalogue projection; no
new C API convenience is added because this host uses the existing C++ interface.

Profiles never invent router callability. No-CEF DesktopApp engine initialization
fails before handler registration; missing host routes remain unavailable even
when a platform has a compiled catalogue profile. A hidden normal Windows app
still uses windowed mode; it does not gain pure headless-backend playback.

Focused tests passed for exact Mac WK/CEF and Linux GTK/OSR projections,
unknown mode, unchanged Windows/mobile flags, direct/generic MCP, body forgery
and absent-route/noCEF refusal. Source-only Maxis attempt was stopped after its
preflight gate failed (outstanding-gates.md); no pass from that attempt is claimed.
Root authorized local Minis fallback for the overloaded Maxis host. The exact
086d607007efee9cdfb807147407f48c64546a8b mirror used existing VS18 Community,
CMake4.4.3 and ignored .cache/native-contracts outputs,one compiler. No CEF,
shipping app,inference,browser or desktop input ran. All shipping relinks and
actual public protocol/capture/UI checks remain platform-owner gates.

## Bounded portable verification, 5 November 2026

Configure flags (PowerShell quotes preserve the policy version):

```text
cmake -S native -B .cache/native-contracts -G "Visual Studio 18 2026" -A x64
  -DKELPIE_BUILD_DESKTOP_ENGINES=ON -DKELPIE_ENABLE_CHROMIUM_DESKTOP=OFF
  -DKELPIE_LOCAL_LLM=OFF -DKELPIE_AI_USE_HTTPLIB=OFF -DBUILD_TESTING=ON
  '-DCMAKE_POLICY_VERSION_MINIMUM:STRING=3.5'
cmake --build .cache/native-contracts --config Debug --target test_mcp_registry
  test_native_extensions test_browser_gateway test_desktop_mcp_server -j1
  -- /p:CL_MPCount=1
ctest --test-dir .cache/native-contracts -C Debug
  -R '^(test_mcp_registry|test_native_extensions|test_browser_gateway|test_desktop_mcp_server)

Owner evidence prerequisites: Mac217f29b69bd5d709d7587f97ea0441307303f1e4
app/test compile; Linux90eb6830eab0e92ca224123f55748e97ed44dce1 actual sandboxed
OSR six-action HTTP capture and8 downloaded/decoded artifacts. Those facts do not
prove Mac runtime,GTK UI,direct/generic MCP/CLI or final release.

  --output-on-failure -j1
```

Configure and build succeeded. CTest4/4 passed in2.13s: registry0.15s,gateway0.30s,
extensions1.39s,desktop MCP0.26s. Build log is preserved under the mirror's
.cache/native-contracts/build.log. Fresh terminating guards permitted configure
at CPU29/49% free23,371,900KiB,build41/50% free23,267,912KiB,and tests53/33%
free22,993,996KiB. Intermediate denied samples launched no child. TEMP/TMP were
task-local for compilation. The mirror contains test outputs only; authoring
remained in the assigned Maxis worktree.

Owner evidence prerequisites: Mac217f29b69bd5d709d7587f97ea0441307303f1e4
app/test compile; Linux90eb6830eab0e92ca224123f55748e97ed44dce1 actual sandboxed
OSR six-action HTTP capture and8 downloaded/decoded artifacts. Those facts do not
prove Mac runtime,GTK UI,direct/generic MCP/CLI or final release.
