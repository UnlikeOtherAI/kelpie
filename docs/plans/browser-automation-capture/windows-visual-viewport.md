# Windows visual viewport binding checkpoint

The strict shared target resolver34a retains layout CSS x/y and returns captured visualViewport:{offsetLeft,offsetTop,width,height,scale}. Native sampler/presentation fields are private; no caller metric override or public endpoint was added.

Perform copies the resolver's captured visual metrics. The sampler observes the same five fields together with innerWidth/innerHeight before and after renderer acquisition. A change from the initial capture viewport or during an in-flight frame refuses CAPTURE_VIEWPORT_CHANGED and retains ordinary valid partials. Captured presentation uses those same frame metrics.

Windows full renderer images include the classic scrollbar gutter. CSSOM specifies innerWidth includes it, while visualViewport.width excludes it. Therefore full-frame rendering must not divide by visible width alone. Pointer and tap points use:
pixelX=(layoutX-offsetLeft)*visualScale*frameWidth/layoutWidth
and the corresponding Y transform. Radius uses the same scale. There is no separate DPR multiplier. Commentary retains its original viewport UI transform and is not shifted by visual panning.

Primary references:
- [CSSOM View visualViewport width and scale](https://drafts.csswg.org/cssom-view/#dom-visualviewport-width).
- [CDP input protocol](https://github.com/ChromeDevTools/devtools-protocol/blob/master/json/browser_protocol.json).

Independent compositor vectors:
- Frame200x200,layout100x100,marker25,25/radius10; visual offset10,5, size50x50,scale2 maps center60,80/radius40.
- A classic-gutter visual90x90 with layout100x100,scale1,offset0 must produce a byte-identical marker to the original center50,50/radius20 frame.
- Zero visible width is refused.
- Commentary must be byte-identical after visual offset changes with layout/scale unchanged.

These are pixel unit assertions, not actual Windows pinch acceptance. Actual f188 native DPR2/visualScale1 trusted center and native spatial capture remain separate evidence. CDP input now subtracts only the same captured visual offsets, without multiplying by scale or DPR. Missing/invalid captured metrics refuse before input. The private mapping helper has pure coordinate regression vectors. Common actual Chromium151 raw touch panning produced scale2/offset54,43/layout scroll0: layout402,120 dispatched unchanged hit BODY at client456,163; subtracting offsets dispatched348,77 and hit the trusted target at client402,120; multiplying again hit BODY. This is protocol proof, not native Windows pinch evidence. Raw common report D:/BuildArtifacts/kelpie/capture-observations-20261104/g07/cdp-input-raw.json SHA1509a77080e0f3c231bfee184632f593219561bb28b07b0602302001fae9337d.

Windows0.1.16 is prepared but remains unsigned/unpublished. Focused Maxis native compilation passed: compositor/store/owner/redactor4/4 in the hard Job65.15s, plus CDP coordinate1/1 in0.80s. Both used one CPU/Normal/2GiB, known SDK/static CRT/LOCAL_LLM=ON, with no app/CEF/llama build. Logs/policies g07-pure-* and g07-input-* are retained. Final candidate replay and actual native scale2/pan remain unclaimed.

A subsequent real f188 API probe confirmed classic gutter behavior: about:blank inner/vv width1042/1042; adding ordinary overflowing content kept innerWidth1042 but changed vvWidth1027, scale1/offset0. Exact within-frame five-metric and per-target fences remain required. The current strict initial-view equality across frames is therefore pending refinement for legal document/gutter transitions before final replay; no final capture compatibility pass is claimed. Facts are in native-sensitive-focus-f188/privacy-focus.json; they are separate from the privacy failure diagnosed by that probe.

The follow-up source keeps exact five-metric target and single-surface fences. Across frames, fixed layout bounds and original decoded pixel dimensions stay fixed; visible width/height may change for scrollbar gutters. New documents adopt their visual offsets/scale after old-document presentation is cleared. Same-document pan/scale changes refuse capture. CDP dispatch now consumes the offset helper at the actual mouse-event construction site; earlier helper-only vector checks did not prove that binding. Native replay remains pending.

## Controlled normal-edit fixture diagnosis

On actual81ed, clicking the textarea wrote the fixture event JSON into an unwrapped pre element. Document scrollWidth grew1027→1739 and clientHeight/visual height fell662→647; layout1042x662, target rectangle and scroll position stayed fixed. The strict input fence returned VIEWPORT_CHANGED. Applying only pre-wrap/overflow-wrap:anywhere through the public existing page interface kept scrollWidth1027 and visual height662; normal trusted fill succeeded.

Raw before/after metrics: D:/BuildArtifacts/kelpie/capture-windows-20261104/native-edit-gutter-control-81ed/post-edit.json. The permanent fixture now wraps its event display. The diagnostic deliberately restores unwrapped style for a negative viewport-change case, then verifies wrapped normal fill. No production target-fence tolerance or automatic retry was introduced.
