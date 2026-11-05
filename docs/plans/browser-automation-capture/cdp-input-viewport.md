# Trusted CDP input versus native visual mapping

Actual bounded Chromium151.0.7922.34 probe on Maxis,5 November2026.
No native production change,OS input,CSS zoom or staged transform was used.
Source tests/capture/cdp-input-viewport.mjs is a fixed synthetic-page diagnostic.

At layout800x600,DPR1,actual CDP page scale2,visualViewport400x300/origin0,
the shared helper resolved partial button center375,120 (visible width50).
Input.dispatchMouseEvent with unchanged layout375,120 produced a trusted
click at client375,120 on the intended target. Applying Canvas scale instead,
750,240,produced trusted client750,240 on BODY. Therefore the observed CDP
path must not reuse native compositor pixel scaling.

The [primary CDP Input definition](https://raw.githubusercontent.com/ChromeDevTools/devtools-protocol/master/pdl/domains/Input.pdl)
describes mouse coordinates as main-frame viewport CSS pixels. The actual
result disambiguates scale behavior for this pinned browser/profile. Native
overlay/export mapping remains separate: layout point minus visual offset,
normalized to captured visual size and owned native renderer dimensions.
No new public endpoint or request authority is needed.

Two original reports remain immutable under common g07 artifacts:
- cdp-input.json SHA b4c4e7a9bee70e4a4f83ea91eae9939c5bf63bcde110335a8d58734c2a9f3620.
- cdp-input-mobile.json SHA5fa3e25820331bfbb379c47cebe265056cda0c3039866c74d670bd7374b1c69d.

The first two high-level gesture attempts returned without nonzero offsets.
Those failures remain immutable. A third approved setup used an actual mobile
context,touch emulation5,content equal to layout viewport (800x600,overflow
hidden),compositor waits and raw CDP touch events. Pinch preparation screenshot
failed and is preserved; the fallback raw single-finger pan produced actual
visual offset54,43 at scale2 with scrollX/Y0 and visual size400x300.

For shared layout center402,120: unchanged CDP402,120 produced trusted
client456,163 on BODY; subtracting the captured offset (348,77) produced trusted
client402,120 on the target; multiplying that relative point by scale
(696,154) produced trustedclient750,197 on BODY. The necessary binding is
CDP x/y = layout x/y minus SAME captured visual offset; no extra DPR/scale
multiplication. Native Canvas/composition retains its separate pixel transform.
Third report cdp-input-raw.json SHA-256:
1509a77080e0f3c231bfee184632f593219561bb28b07b0602302001fae9337d.
Job12.495s/free28,257,980KiB; every observed leaf1/Normal,2GiB,closed normally.
No further browser attempt or native production edit followed.

Pinned Chromium149 primary trace:
[InputHandler::DispatchMouseEvent and ScaleFactor](https://github.com/chromium/chromium/blob/149.0.7827.201/content/browser/devtools/protocol/input_handler.cc#L1259)
construct widget coordinates with browser/embedding/pinch scale already applied;
[WebMouseEvent root transform](https://github.com/chromium/chromium/blob/149.0.7827.201/third_party/blink/common/input/web_mouse_event.cc#L30)
divides frame scale and adds frame translation. This is consistent with the
measured offset result; do not apply compositor scaling a second time.

Each job owned one existing sandboxed browser and enforced hard affinity1/
Normal/2GiB with30s deadline. Observed browser/GPU/renderer/conhost leaves
matched. First job3.071s/free29,516,064KiB; second2.945s/free29,411,872KiB.
Both closed their own browsers. Primary specification and bounded actual
facts were sent to Windows/Linux owners before their input freeze.

## DOM click coordinate quantization

Android real pinch reported fractional shared centers291.60186/400.88675
and click clientX291/400. Chromium's
[MouseEvent getter](https://raw.githubusercontent.com/chromium/chromium/main/third_party/blink/renderer/core/events/mouse_event.h)
floors stored client coordinates. Preserve fractional resolver/native overlay
math; check that MouseEvent readback equals its expected floor (error<1CSSpx),
rather than loosening visible-center or exported marker-pixel registration.
This is declared event readback behavior,not permission to shift the target.
Native fixture/pixel verification still must run.
