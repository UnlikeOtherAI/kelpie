# Kelpie browser engines and worker backends

This document describes implemented repository bindings. An engine available
upstream is not automatically a Kelpie renderer, and a CDP connection does not
establish support for every browser-control method.

## Implemented native renderers

| Platform/build | Renderer in this repository | Evidence and limits |
| --- | --- | --- |
| iOS/iPadOS | WKWebView | `apps/ios/Kelpie/Browser/BrowserState.swift` and the WebKit native gateway. No alternative-engine binding is implemented. |
| Android | System Android WebView | `apps/android/app/src/main/java/com/kelpie/browser`. The app uses the installed WebView and its native/CDP interfaces. No GeckoView binding is implemented. |
| macOS | WKWebView or Chromium through CEF | `apps/macos/Kelpie/Renderer/RendererState.swift` selects WebKit or Chromium. There is no Gecko/Firefox renderer in the current abstraction. |
| Windows release | Chromium through CEF | `apps/windows/CMakeLists.txt` requires the pinned CEF SDK for Release and packages the sandboxed bootstrap and matching runtime assets. It does not use WebView2. |
| Linux with CEF | Chromium through the shared desktop engine | `apps/linux/CMakeLists.txt` enables `native/engine-chromium-desktop` when its CEF SDK is present. GTK chrome is optional for the headless configuration. |
| Linux without CEF | No live browser renderer | The fallback serves metadata and supported legacy controls. Its canonical gateway sets `browserAvailable:false` and does not advertise live DOM observations or pixel capture. |
| Windows without CEF | Development fallback only | The CMake Release configuration refuses this build. A development fallback must not be presented as a shipping Chromium browser. |

These statements were checked against repository revision
`c01b2038bdb663cb9d5c7add134d587635da17ca`. They do not assert that an unbuilt
candidate or an installed release has passed a new platform acceptance run.

The shared Windows/Linux CEF implementation is in
[`native/engine-chromium-desktop`](../native/engine-chromium-desktop).
Native gateway bindings and verification are described in
[native-browser-gateway.md](api/native-browser-gateway.md).
Use each running browser's actual capabilities; engine names alone do not grant
input, screenshot, tab, private-realm or storage-isolation support.

## Browser-control adapters and allocation

The shared [browser-control API](api/browser-control.md) can wrap authorized
Playwright pages supplied by an operator. This is an adapter, not an additional
native engine shipped inside Kelpie. Allocation and authentication stay outside
the page implementation. A binding may expose only pages owned by its session.

A caller requesting isolated storage must receive actual isolated storage or an
explicit refusal. A fresh tab in a shared native/browser context still shares its
cookies and storage. A model cannot attach an endpoint, import a human browser
profile, or promote another session's tab identifier into ownership.

Native desktop tabs/partitions and external worker contexts have different
lifecycle support. Do not approximate one with the other or infer mobile
background execution from a desktop worker capability.

## Restricted Lightpanda experiment

Lightpanda is an optional external-process worker experiment, not a Kelpie native
renderer or a Chromium replacement. The integration plan and evidence ledger are
in [desktop-backend.md](plans/browser-automation-capture/desktop-backend.md).

The operator must provide an authorized connection, bounded process lifetime and
resources, and enforced network egress policy. A model-facing browser request
cannot choose an attachment URL. The adapter must use an explicit verified method
inventory and reject other methods before page access. Exact binary version/hash
and corpus results belong in the acceptance record.

Upstream documents Linux/macOS binaries, Windows through WSL2, no native Android
binary, and text-only PNG/PDF output. That output cannot satisfy Kelpie's canonical
pixel-screenshot, visual geometry, pointer, video or GIF contracts.
See the [official Lightpanda repository](https://github.com/lightpanda-io/browser).

Kelpie does not copy, link, bundle or port Lightpanda's AGPL implementation in this
experiment. Operator installation of an external process does not imply native
platform support or universal CDP conformance. No vendor speed or memory benchmark
is a Kelpie acceptance result.

The existing value-free snapshot/extraction readers use actual visibility
evidence. A layout-independent worker must not silently replace those guarantees
with raw DOM content or report a misleading successful empty result.

## Upstream options and Apple distribution

GeckoView is an Android embeddable engine upstream, but Kelpie does not implement
it. It is not the desktop Gecko binding described by an older version of this
document. See [Mozilla's GeckoView documentation](https://mozilla.github.io/geckoview/).

No iOS alternative-engine approval, locale-based eligibility implementation,
Firefox CDP integration, Apple compliance dashboard deployment or engine update
automation is established by this document. The [engine monitoring design](engine-monitoring.md)
is a separate proposal, not evidence that those services are running.

Any future Apple alternative-engine work must follow the current applicable
Apple program and entitlement requirements. A locale string or an invented
Info.plist entitlement is not proof of eligibility or approval. Apple's current
program documentation is the authority; consult
[Using alternative browser engines in the European Union](https://developer.apple.com/support/alternative-browser-engines/)
before designing such a change. This repository currently uses WKWebView on iOS.
