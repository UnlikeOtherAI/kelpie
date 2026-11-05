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

Focused tests are drafted for exact Mac WK/CEF and Linux GTK/OSR projections,
unknown mode, unchanged Windows/mobile flags, direct/generic MCP, body forgery
and absent-route/noCEF refusal. Source-only Maxis attempt was stopped after its
preflight gate failed (outstanding-gates.md); no pass from that attempt is claimed.
The Minis mirror may run only noCEF/noLLM core/CAPI/stub targets,one compiler,
using existing toolchain and ignored outputs. All shipping relinks and actual
public protocol/capture/UI checks remain platform-owner gates.

Owner evidence prerequisites: Mac217f29b69bd5d709d7587f97ea0441307303f1e4
app/test compile; Linux90eb6830eab0e92ca224123f55748e97ed44dce1 actual sandboxed
OSR six-action HTTP capture and8 downloaded/decoded artifacts. Those facts do not
prove Mac runtime,GTK UI,direct/generic MCP/CLI or final release.
