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

Supported synthetic pinch/pan commands returned but did not produce nonzero
visual offsets in either desktop or explicit mobile-device emulation. The
latter profile is labelled in source/report. No nonzero-offset CDP input claim
is made; native iOS/Android real pinch evidence is separate. Do not infer a
conversion or broaden native input from the unsuccessful gesture branches.

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
